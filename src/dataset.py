"""
dataset.py
----------
Dataset loading and target-distribution generation for personality pretraining.

Source dataset:  FuseAI/FuseChat-Mixture  (HuggingFace Datasets Hub)

Pipeline per sample:
  1. Extract text from the conversation (user turns or full conversation).
  2. Embed text → 1536-dim vector  (via EmbeddingBackend).
  3. Compute cosine similarity between the text vector and each of the 325
     personality token embeddings.                           [sim ∈ (-1, 1)]
  4. Apply a temperature-scaled softmax → soft label distribution.
                                                             [target ∈ (0, 1)]
  5. The PersonalityModel is then trained with BCEWithLogitsLoss to predict
     these soft labels.

Important design notes:
  • Token embeddings are built ONCE from the personality token strings and
    reused for every training sample.
  • Embeddings are cached to disk so re-runs skip expensive recomputation.
  • The token ordering is FIXED (from personality-tokens.json).  Do not sort
    or shuffle the token list.

Cache layout  (inside  <output_dir>/cache/):
  embeddings.pt   — FloatTensor (N_samples, 1536)
  targets.pt      — FloatTensor (N_samples, 325)
  metadata.json   — records model name, token file hash, N_samples
"""

import json
import hashlib
from pathlib import Path
from typing import List, Optional, Tuple

import torch
import torch.nn.functional as F
from torch.utils.data import Dataset
from datasets import load_dataset

from .tokens import TOKENS, VOCAB_SIZE


# ── Constants ──────────────────────────────────────────────────────────────────

# Temperature for converting cosine similarities to a soft distribution.
# Lower temperature  → sharper (fewer tokens activated strongly)
# Higher temperature → flatter (more tokens share probability mass)
TARGET_TEMPERATURE: float = 0.07

# Maximum number of training samples drawn from the dataset.
# Increase for better coverage; decrease for faster experimentation.
MAX_SAMPLES: int = 50_000

# HuggingFace dataset identifier.
DATASET_NAME: str = "FuseAI/FuseChat-Mixture"

# Maximum characters extracted from each conversation sample.
# Truncating keeps embedding time manageable.
MAX_CHARS_PER_SAMPLE: int = 1_024


# ── Text extraction ────────────────────────────────────────────────────────────

def extract_text(sample: dict) -> Optional[str]:
    """
    Extract a meaningful text string from one FuseChat-Mixture sample.

    The dataset uses a "conversations" field (list of {from, value} dicts).
    We concatenate all human turns to capture the stylistic signal we care
    about, then truncate to MAX_CHARS_PER_SAMPLE.

    Returns None if no usable text is found.
    """
    conversations = sample.get("conversations") or sample.get("messages") or []

    parts: List[str] = []
    for turn in conversations:
        # Collect user-side utterances (labelled "human" or "user").
        role = (turn.get("from") or turn.get("role") or "").lower()
        content = turn.get("value") or turn.get("content") or ""
        if role in ("human", "user") and content.strip():
            parts.append(content.strip())

    if not parts:
        # Fall back to any non-empty text field in the sample.
        for key in ("text", "prompt", "instruction", "input"):
            val = sample.get(key, "")
            if isinstance(val, str) and val.strip():
                return val.strip()[:MAX_CHARS_PER_SAMPLE]
        return None

    combined = " ".join(parts)
    return combined[:MAX_CHARS_PER_SAMPLE]


# ── Token embedding construction ───────────────────────────────────────────────

def build_token_embeddings(embedding_backend) -> torch.Tensor:
    """
    Embed each of the 325 personality token strings using the provided backend.

    Returns:
        token_embs: (325, 1536) float32 tensor, L2-normalised row-wise.

    These embeddings define the "personality basis vectors" in the shared
    embedding space.  Cosine similarity between a text embedding and each row
    of token_embs produces the raw similarity score for that token.
    """
    print(f"[dataset] Embedding {VOCAB_SIZE} personality tokens ...")
    token_embs = embedding_backend.embed(TOKENS, batch_size=64, normalize=True)
    # Ensure rows are unit-norm for reliable cosine similarity via dot product.
    token_embs = F.normalize(token_embs, p=2, dim=-1)
    print(f"[dataset] Token embeddings shape: {token_embs.shape}")
    return token_embs  # (325, 1536)


# ── Soft target generation ─────────────────────────────────────────────────────

def compute_soft_targets(
    text_embeddings: torch.Tensor,   # (N, 1536)
    token_embeddings: torch.Tensor,  # (325, 1536)
    temperature: float = TARGET_TEMPERATURE,
) -> torch.Tensor:
    """
    Convert per-sample text embeddings into soft label distributions over the
    325 personality tokens.

    Process:
      1. Cosine similarity matrix  S[i, j] = dot(text[i], token[j])
         (dot product == cosine similarity because both are L2-normalised)
      2. Temperature-scaled softmax over the token dimension →  target[i, :]
         This is a valid probability distribution (sums to 1) that concentrates
         mass on the most semantically similar personality tokens.

    Args:
        text_embeddings:  (N, 1536) L2-normalised.
        token_embeddings: (325, 1536) L2-normalised.
        temperature:      Softmax sharpness. Default 0.07 produces a fairly
                          peaked distribution.

    Returns:
        targets: (N, 325) float32 soft label distribution for BCEWithLogitsLoss.
    """
    # S[i, j] = cosine similarity between sample i and token j.
    # Shape: (N, 325)
    similarities = text_embeddings @ token_embeddings.T

    # Scale by inverse temperature before softmax to sharpen distribution.
    scaled = similarities / temperature

    # Softmax across the token dimension → probability distribution.
    targets = torch.softmax(scaled, dim=-1)

    return targets  # (N, 325)


# ── Cache helpers ──────────────────────────────────────────────────────────────

def _token_hash() -> str:
    """Short hash of the token list to invalidate cache if tokens change."""
    token_str = json.dumps(TOKENS, sort_keys=False).encode()
    return hashlib.md5(token_str).hexdigest()[:8]


def _save_cache(
    cache_dir: Path,
    embeddings: torch.Tensor,
    targets: torch.Tensor,
    model_name: str,
) -> None:
    """Persist embeddings + targets tensors and metadata to cache_dir."""
    cache_dir.mkdir(parents=True, exist_ok=True)
    torch.save(embeddings, cache_dir / "embeddings.pt")
    torch.save(targets, cache_dir / "targets.pt")
    meta = {
        "model_name": model_name,
        "token_hash": _token_hash(),
        "n_samples": len(embeddings),
        "vocab_size": VOCAB_SIZE,
    }
    with open(cache_dir / "metadata.json", "w") as fh:
        json.dump(meta, fh, indent=2)
    print(f"[dataset] Cache saved → {cache_dir}")


def _load_cache(
    cache_dir: Path,
    model_name: str,
) -> Optional[Tuple[torch.Tensor, torch.Tensor]]:
    """
    Try to load embeddings and targets from cache.

    Returns (embeddings, targets) if cache is valid, None otherwise.
    Cache is considered invalid if:
      - metadata.json is missing
      - the embedding model name changed
      - the token list hash changed (token file was modified)
    """
    meta_path = cache_dir / "metadata.json"
    if not meta_path.exists():
        return None

    with open(meta_path) as fh:
        meta = json.load(fh)

    if meta.get("model_name") != model_name:
        print("[dataset] Cache miss: embedding model changed.")
        return None
    if meta.get("token_hash") != _token_hash():
        print("[dataset] Cache miss: personality-tokens.json changed.")
        return None

    emb_path = cache_dir / "embeddings.pt"
    tgt_path = cache_dir / "targets.pt"
    if not emb_path.exists() or not tgt_path.exists():
        return None

    print(f"[dataset] Loading cached embeddings from {cache_dir} ...")
    embeddings = torch.load(emb_path, map_location="cpu")
    targets = torch.load(tgt_path, map_location="cpu")
    print(f"[dataset] Loaded {len(embeddings)} samples from cache.")
    return embeddings, targets


# ── PyTorch Dataset ────────────────────────────────────────────────────────────

class PersonalityDataset(Dataset):
    """
    PyTorch Dataset for personality model pretraining.

    Each item is:
        {
            "embedding": FloatTensor(1536,),   # pre-computed text embedding
            "targets":   FloatTensor(325,),    # soft label distribution
        }

    Building the dataset involves:
      1. Streaming FuseChat-Mixture and extracting text samples.
      2. Embedding all samples with the provided embedding_backend.
      3. Building token embeddings (once).
      4. Computing soft targets from cosine similarities.

    Everything is cached after the first run.
    """

    def __init__(
        self,
        embedding_backend,
        output_dir: Path,
        max_samples: int = MAX_SAMPLES,
        temperature: float = TARGET_TEMPERATURE,
        force_rebuild: bool = False,
    ) -> None:
        """
        Args:
            embedding_backend: Instance of LocalEmbeddingBackend or OpenAIEmbeddingBackend.
            output_dir:        Root directory for caching (e.g., "outputs/").
            max_samples:       Maximum number of training samples to use.
            temperature:       Softmax temperature for target generation.
            force_rebuild:     If True, ignore existing cache and recompute.
        """
        self.output_dir = Path(output_dir)
        self.cache_dir = self.output_dir / "cache"

        # Infer a model name string for cache validation.
        model_name = getattr(
            embedding_backend,
            "model",
            getattr(
                getattr(embedding_backend, "encoder", None),
                "config",
                type(embedding_backend).__name__,  # fallback
            ),
        )
        if hasattr(model_name, "name_or_path"):
            model_name = model_name.name_or_path

        # Try loading from cache first.
        if not force_rebuild:
            cached = _load_cache(self.cache_dir, str(model_name))
            if cached is not None:
                self.embeddings, self.targets = cached
                # Respect max_samples even on cache hit.
                if len(self.embeddings) > max_samples:
                    self.embeddings = self.embeddings[:max_samples]
                    self.targets = self.targets[:max_samples]
                return

        # ── Build dataset from scratch ─────────────────────────────────────────

        print(f"[dataset] Building dataset from {DATASET_NAME} ...")
        raw_texts = self._load_texts(max_samples)
        print(f"[dataset] Extracted {len(raw_texts)} text samples.")

        # Embed all text samples.
        print("[dataset] Embedding text samples (this may take a while) ...")
        self.embeddings = embedding_backend.embed(
            raw_texts, batch_size=64, normalize=True
        )  # (N, 1536)

        # Build token embeddings for target generation.
        token_embs = build_token_embeddings(embedding_backend)  # (325, 1536)

        # Compute soft target distributions.
        print("[dataset] Computing soft targets from cosine similarities ...")
        self.targets = compute_soft_targets(
            self.embeddings, token_embs, temperature=temperature
        )  # (N, 325)

        # Persist to cache for future runs.
        _save_cache(self.cache_dir, self.embeddings, self.targets, str(model_name))

    @staticmethod
    def _load_texts(max_samples: int) -> List[str]:
        """
        Stream FuseChat-Mixture and collect up to max_samples text strings.

        Uses streaming mode to avoid downloading the entire dataset before
        processing starts.  The dataset is very large, so we stop as soon as
        we have enough valid samples.
        """
        texts: List[str] = []

        # streaming=True avoids materialising the full dataset on disk.
        dataset = load_dataset(
            DATASET_NAME,
            split="train",
            streaming=True,
            trust_remote_code=True,
        )

        for sample in dataset:
            text = extract_text(sample)
            if text:
                texts.append(text)
            if len(texts) >= max_samples:
                break

        return texts

    # ── Dataset protocol ────────────────────────────────────────────────────────

    def __len__(self) -> int:
        return len(self.embeddings)

    def __getitem__(self, idx: int) -> dict:
        return {
            "embedding": self.embeddings[idx],  # (1536,) float32
            "targets": self.targets[idx],        # (325,)  float32
        }
