"""
embeddings.py
-------------
Text → 1536-dimensional embedding vectors.

This module is responsible ONLY for converting raw text strings into the
1536-dim float32 vectors that the PersonalityModel consumes.  It is NOT part
of the Core ML graph — embedding generation happens outside the model boundary.

Two backends are supported:

  1. OpenAI (default if OPENAI_API_KEY is set in the environment)
     Model: text-embedding-3-small  → native 1536-dim output.
     Requires: `pip install openai`

  2. Local HuggingFace Transformers  (fallback / fully offline)
     Any encoder model is supported.  If the model's hidden size ≠ 1536, a
     learned linear projection (EmbeddingProjector) maps it to 1536.
     Default local model: "sentence-transformers/all-MiniLM-L6-v2"  (hidden_size=384)

Usage:
    from src.embeddings import EmbeddingBackend
    backend = EmbeddingBackend.from_env()          # auto-selects OpenAI or local
    vecs = backend.embed(["hello world", "..."])   # returns (N, 1536) tensor
"""

import os
import math
from typing import List, Optional

import torch
import torch.nn as nn
import torch.nn.functional as F
from transformers import AutoTokenizer, AutoModel

# ── Constants ──────────────────────────────────────────────────────────────────

TARGET_DIM: int = 1536          # Canonical embedding dimension expected by PersonalityModel
OPENAI_MODEL: str = "text-embedding-3-small"  # 1536-dim native output
DEFAULT_LOCAL_MODEL: str = "sentence-transformers/all-MiniLM-L6-v2"  # 384-dim → projected to 1536
LOCAL_MAX_LENGTH: int = 512     # Token truncation limit for local encoder


# ── Device selection ────────────────────────────────────────────────────────────

def _resolve_device(device: Optional[str] = None) -> torch.device:
    """
    Choose a torch.device, preferring CUDA by default.

    Args:
        device: "auto" (or None) to auto-select, or explicit "cuda" | "mps" | "cpu".
    """
    if device is None:
        device = "auto"

    choice = device.lower()
    if choice == "auto":
        if torch.cuda.is_available():
            return torch.device("cuda")
        if torch.backends.mps.is_available():
            return torch.device("mps")
        return torch.device("cpu")

    if choice == "cuda":
        if not torch.cuda.is_available():
            raise RuntimeError("CUDA requested but no CUDA device is available.")
        return torch.device("cuda")
    if choice == "mps":
        if not torch.backends.mps.is_available():
            raise RuntimeError("MPS requested but no MPS device is available.")
        return torch.device("mps")
    if choice == "cpu":
        return torch.device("cpu")

    raise ValueError(f"Unsupported device '{device}'. Use 'auto', 'cuda', 'mps', or 'cpu'.")


# ── Projection layer (local backend only) ─────────────────────────────────────

class EmbeddingProjector(nn.Module):
    """
    Single linear layer that maps any hidden_size → TARGET_DIM (1536).

    Used when the local HuggingFace model does not natively output 1536 dims.
    The projector is trained jointly with the personality model during
    pretraining so that the full pipeline produces coherent representations.
    After pretraining, projection weights are frozen alongside the encoder.
    """

    def __init__(self, in_dim: int, out_dim: int = TARGET_DIM) -> None:
        super().__init__()
        self.linear = nn.Linear(in_dim, out_dim, bias=True)
        nn.init.xavier_uniform_(self.linear.weight)
        nn.init.zeros_(self.linear.bias)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (batch, in_dim)  →  output: (batch, 1536)
        return self.linear(x)


# ── Local HuggingFace backend ─────────────────────────────────────────────────

class LocalEmbeddingBackend:
    """
    Computes mean-pooled, L2-normalised sentence embeddings using a local
    HuggingFace encoder model.

    If the model's hidden_size ≠ TARGET_DIM (1536), an EmbeddingProjector is
    automatically attached.  The projector lives on the same device as the
    encoder and can be checkpointed alongside PersonalityModel weights.
    """

    def __init__(
        self,
        model_name: str = DEFAULT_LOCAL_MODEL,
        device: Optional[str] = None,
        projector: Optional[EmbeddingProjector] = None,
    ) -> None:
        self.device = _resolve_device(device)
        print(f"[LocalEmbeddingBackend] Loading '{model_name}' on {self.device}")

        # Load tokenizer and frozen encoder.
        self.tokenizer = AutoTokenizer.from_pretrained(model_name)
        self.encoder = AutoModel.from_pretrained(model_name).to(self.device)
        self.encoder.eval()  # Always in eval; we never backprop through this

        # Disable gradients on the encoder — it is a fixed feature extractor.
        for param in self.encoder.parameters():
            param.requires_grad = False

        # Attach a projector if the hidden size does not match TARGET_DIM.
        hidden_size: int = self.encoder.config.hidden_size
        if hidden_size != TARGET_DIM:
            print(
                f"[LocalEmbeddingBackend] hidden_size={hidden_size} ≠ {TARGET_DIM}; "
                "attaching EmbeddingProjector"
            )
            # Use provided projector (e.g., loaded from checkpoint) or create new.
            self.projector: Optional[EmbeddingProjector] = (
                projector if projector is not None
                else EmbeddingProjector(hidden_size, TARGET_DIM).to(self.device)
            )
        else:
            self.projector = projector  # None if not needed

        self.hidden_size = hidden_size

    @torch.no_grad()
    def embed(
        self,
        texts: List[str],
        batch_size: int = 64,
        normalize: bool = True,
    ) -> torch.Tensor:
        """
        Convert a list of strings to a (N, 1536) float32 tensor.

        Steps per mini-batch:
          1. Tokenise with padding + truncation.
          2. Run the frozen encoder to get the last hidden state.
          3. Mean-pool over non-padding token positions.
          4. Optional L2 normalisation (enabled by default).
          5. Apply EmbeddingProjector if hidden_size ≠ 1536.

        Args:
            texts:      List of N strings.
            batch_size: Tokenisation + inference batch size.
            normalize:  If True, L2-normalise the final vectors.

        Returns:
            Tensor of shape (N, 1536) on CPU.
        """
        all_vecs: List[torch.Tensor] = []

        for i in range(0, len(texts), batch_size):
            batch_texts = texts[i : i + batch_size]

            # Tokenise — returns input_ids, attention_mask on the target device.
            encoded = self.tokenizer(
                batch_texts,
                padding=True,
                truncation=True,
                max_length=LOCAL_MAX_LENGTH,
                return_tensors="pt",
            ).to(self.device)

            # Forward through frozen encoder.
            outputs = self.encoder(**encoded)
            # last_hidden_state: (batch, seq_len, hidden_size)
            last_hidden = outputs.last_hidden_state

            # Mean-pool over non-padding positions only.
            # attention_mask: (batch, seq_len) — 1 for real tokens, 0 for padding.
            mask = encoded["attention_mask"].unsqueeze(-1).float()  # (batch, seq, 1)
            summed = (last_hidden * mask).sum(dim=1)                # (batch, hidden)
            counts = mask.sum(dim=1).clamp(min=1e-9)               # (batch, 1)
            pooled = summed / counts                                 # (batch, hidden)

            # Project to 1536 if necessary (requires grad only when training projector).
            if self.projector is not None:
                pooled = self.projector(pooled)

            # L2 normalise so cosine similarity = dot product (numerically stable).
            if normalize:
                pooled = F.normalize(pooled, p=2, dim=-1)

            all_vecs.append(pooled.cpu())

        return torch.cat(all_vecs, dim=0)  # (N, 1536)


# ── OpenAI backend ─────────────────────────────────────────────────────────────

class OpenAIEmbeddingBackend:
    """
    Thin wrapper around the OpenAI Embeddings API.

    Requires:
      - `pip install openai`
      - OPENAI_API_KEY environment variable.

    Returns L2-normalised 1536-dim vectors (text-embedding-3-small already
    produces unit-norm outputs, so normalisation is a no-op in practice).
    """

    def __init__(self, model: str = OPENAI_MODEL) -> None:
        try:
            import openai
        except ImportError:
            raise ImportError(
                "openai package not found. Install it with: pip install openai"
            )
        self.client = openai.OpenAI()  # reads OPENAI_API_KEY from environment
        self.model = model

    def embed(
        self,
        texts: List[str],
        batch_size: int = 512,
        normalize: bool = True,
    ) -> torch.Tensor:
        """
        Call the OpenAI Embeddings endpoint and return (N, 1536) tensor.

        Args:
            texts:      List of N strings.
            batch_size: Max strings per API call (OpenAI limit is 2048).
            normalize:  If True, L2-normalise (usually a no-op for ada models).

        Returns:
            Tensor of shape (N, 1536) on CPU.
        """
        all_vecs: List[torch.Tensor] = []

        for i in range(0, len(texts), batch_size):
            batch_texts = texts[i : i + batch_size]
            response = self.client.embeddings.create(
                model=self.model,
                input=batch_texts,
            )
            # response.data is a list of Embedding objects, one per input string.
            vecs = torch.tensor(
                [e.embedding for e in response.data], dtype=torch.float32
            )  # (batch, 1536)

            if normalize:
                vecs = F.normalize(vecs, p=2, dim=-1)

            all_vecs.append(vecs)

        return torch.cat(all_vecs, dim=0)  # (N, 1536)


# ── Auto-selecting factory ─────────────────────────────────────────────────────

class EmbeddingBackend:
    """
    Factory that selects the appropriate embedding backend.

    Call EmbeddingBackend.from_env() to automatically use OpenAI if
    OPENAI_API_KEY is set, otherwise fall back to the local model.
    """

    @staticmethod
    def from_env(
        local_model: str = DEFAULT_LOCAL_MODEL,
        device: Optional[str] = None,
    ) -> "LocalEmbeddingBackend | OpenAIEmbeddingBackend":
        """
        Auto-select backend based on environment:
          - OPENAI_API_KEY present  →  OpenAIEmbeddingBackend
          - Otherwise               →  LocalEmbeddingBackend

        Args:
            local_model: HuggingFace model ID for the local fallback.
            device:      Torch device string for the local backend.
        """
        if isinstance(device, torch.device):
            device = device.type

        if os.getenv("OPENAI_API_KEY"):
            print("[EmbeddingBackend] OPENAI_API_KEY found — using OpenAI backend.")
            return OpenAIEmbeddingBackend()
        else:
            print(
                "[EmbeddingBackend] No OPENAI_API_KEY — using local backend "
                f"({local_model})."
            )
            return LocalEmbeddingBackend(model_name=local_model, device=device)
