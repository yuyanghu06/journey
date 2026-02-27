"""
model.py
--------
Defines the PersonalityModel architecture.

Pipeline (all dimensions are explicit):
    Input  : (batch, 1536)  — pre-computed text embedding
    ↓ input_projection      — linear 1536→LATENT_DIM
    ↓ encoder               — N× lightweight attention blocks (frozen backbone)
    ↓ projection            — linear LATENT_DIM→325       (trainable head)
    ↓ (+ bias)
    Output : (batch, 325)   — raw logits; apply torch.sigmoid for probabilities

Design constraints (from the architecture spec):
  • The encoder layers are treated as a frozen backbone after pretraining.
  • The projection matrix + bias MUST remain replaceable so GRPO can update them
    on device (Core ML updatable model).
  • No dynamic vocabulary; output is always exactly 325 dimensions.
  • Keep the graph simple for Core ML compatibility (avoid dynamic shapes, loops).
"""

import torch
import torch.nn as nn

from .tokens import VOCAB_SIZE

# ── Hyperparameters ────────────────────────────────────────────────────────────

EMBEDDING_DIM: int = 1536   # Input embedding dimension (matches OpenAI ada-002 / local projection)
LATENT_DIM: int = 512       # Internal representation width
NUM_HEADS: int = 8           # Multi-head attention heads (LATENT_DIM must be divisible by NUM_HEADS)
NUM_ENCODER_LAYERS: int = 2  # Depth of the frozen encoder backbone
FFN_DIM: int = LATENT_DIM * 4  # Feed-forward inner dimension in transformer layers
DROPOUT: float = 0.1        # Dropout applied during training only


# ── Encoder building blocks ──────────────────────────────────────────────────────


class SimpleSelfAttention(nn.Module):
    """
    Minimal self-attention built from Core ML–friendly primitives.
    Avoids the fused Transformer encoder op that coremltools cannot lower.
    """

    def __init__(self, dim: int, num_heads: int, dropout: float) -> None:
        super().__init__()
        if dim % num_heads != 0:
            raise ValueError("latent_dim must be divisible by num_heads")

        self.num_heads = num_heads
        self.head_dim = dim // num_heads
        self.scale = self.head_dim**-0.5

        self.q_proj = nn.Linear(dim, dim)
        self.k_proj = nn.Linear(dim, dim)
        self.v_proj = nn.Linear(dim, dim)
        self.out_proj = nn.Linear(dim, dim)
        self.attn_drop = nn.Dropout(dropout)
        self.proj_drop = nn.Dropout(dropout)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # x: (batch, seq_len, dim)
        bsz, seq_len, dim = x.shape
        q = self.q_proj(x)
        k = self.k_proj(x)
        v = self.v_proj(x)

        # Reshape to (batch, heads, seq_len, head_dim)
        def _reshape(t: torch.Tensor) -> torch.Tensor:
            return t.view(bsz, seq_len, self.num_heads, self.head_dim).transpose(1, 2)

        q = _reshape(q)
        k = _reshape(k)
        v = _reshape(v)

        # Attention weights: (batch, heads, seq, seq)
        attn = torch.matmul(q * self.scale, k.transpose(-2, -1))
        attn = torch.softmax(attn, dim=-1)
        attn = self.attn_drop(attn)

        # Weighted sum of values
        out = torch.matmul(attn, v)  # (batch, heads, seq_len, head_dim)
        out = out.transpose(1, 2).contiguous().view(bsz, seq_len, dim)
        out = self.out_proj(out)
        out = self.proj_drop(out)
        return out


class SimpleEncoderLayer(nn.Module):
    """
    Lightweight encoder layer: LayerNorm → SelfAttention → residual →
    LayerNorm → FFN → residual. Uses primitives that Core ML can convert.
    """

    def __init__(self, dim: int, num_heads: int, ffn_dim: int, dropout: float) -> None:
        super().__init__()
        self.norm1 = nn.LayerNorm(dim)
        self.attn = SimpleSelfAttention(dim, num_heads, dropout)
        self.dropout = nn.Dropout(dropout)

        self.norm2 = nn.LayerNorm(dim)
        self.ffn = nn.Sequential(
            nn.Linear(dim, ffn_dim),
            nn.GELU(),
            nn.Dropout(dropout),
            nn.Linear(ffn_dim, dim),
            nn.Dropout(dropout),
        )

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        # Self-attention block
        attn_out = self.attn(self.norm1(x))
        x = x + self.dropout(attn_out)

        # Feed-forward block
        ffn_out = self.ffn(self.norm2(x))
        x = x + ffn_out
        return x


# ── Model ──────────────────────────────────────────────────────────────────────

class PersonalityModel(nn.Module):
    """
    Lightweight on-device personality inference model.

    The model is split into two functional sections:
      1. Frozen backbone  — input_projection + encoder
         These weights are fixed after pretraining and are NOT updated during
         on-device GRPO fine-tuning.

      2. Trainable head   — projection (nn.Linear) + bias (nn.Parameter)
         These weights CAN be replaced / updated on device. Core ML exports
         them as updatable parameters.
    """

    def __init__(
        self,
        embedding_dim: int = EMBEDDING_DIM,
        latent_dim: int = LATENT_DIM,
        num_heads: int = NUM_HEADS,
        num_encoder_layers: int = NUM_ENCODER_LAYERS,
        ffn_dim: int = FFN_DIM,
        dropout: float = DROPOUT,
        vocab_size: int = VOCAB_SIZE,
    ) -> None:
        super().__init__()

        # ── Backbone ────────────────────────────────────────────────────────────

        # Project raw 1536-dim embedding into the encoder's working dimension.
        # This is part of the frozen backbone.
        self.input_projection = nn.Linear(embedding_dim, latent_dim)

        # Export-friendly encoder: stack of lightweight attention blocks.
        self.encoder_layers = nn.ModuleList(
            [
                SimpleEncoderLayer(
                    dim=latent_dim,
                    num_heads=num_heads,
                    ffn_dim=ffn_dim,
                    dropout=dropout,
                )
                for _ in range(num_encoder_layers)
            ]
        )

        # ── Trainable head ───────────────────────────────────────────────────────

        # Linear projection: latent representation → 325 logits.
        # This layer's weights are the primary target for on-device GRPO updates.
        self.projection = nn.Linear(latent_dim, vocab_size, bias=False)

        # Separate bias parameter keeps it independently accessible for GRPO,
        # and makes it straightforward to replace just the bias on device.
        self.output_bias = nn.Parameter(torch.zeros(vocab_size))

        # ── Weight initialisation ────────────────────────────────────────────────

        self._init_weights()

    # ── Initialisation ─────────────────────────────────────────────────────────

    def _init_weights(self) -> None:
        """Xavier-uniform for linear layers; zero bias for stable early training."""
        nn.init.xavier_uniform_(self.input_projection.weight)
        nn.init.zeros_(self.input_projection.bias)
        nn.init.xavier_uniform_(self.projection.weight)
        # output_bias is already zero-initialised in __init__

    # ── Forward ────────────────────────────────────────────────────────────────

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        """
        Forward pass.

        Args:
            x: (batch_size, 1536) — pre-computed, L2-normalised text embeddings.

        Returns:
            logits: (batch_size, 325) — raw logits before sigmoid.
                    Apply torch.sigmoid(logits) to obtain the token probability
                    distribution at inference time.
        """
        # ── Step 1: project embedding → latent space ──────────────────────────
        # Shape: (batch, 1536) → (batch, LATENT_DIM)
        h = self.input_projection(x)

        # ── Step 2: add sequence dimension for transformer ─────────────────────
        # TransformerEncoder expects (batch, seq_len, dim).
        # We treat each embedding as a single-token sequence (seq_len = 1).
        h = h.unsqueeze(1)  # (batch, 1, LATENT_DIM)

        # ── Step 3: encoder forward pass ──────────────────────────────────────
        # With seq_len=1 there is no meaningful self-attention across tokens,
        # but the feed-forward sub-layers still apply non-linear transformation
        # to the latent representation.
        for layer in self.encoder_layers:
            h = layer(h)  # (batch, 1, LATENT_DIM)

        # ── Step 4: remove sequence dimension ─────────────────────────────────
        h = h.squeeze(1)  # (batch, LATENT_DIM)

        # ── Step 5: project to vocabulary logits ──────────────────────────────
        logits = self.projection(h) + self.output_bias  # (batch, 325)

        return logits

    # ── Utility helpers ────────────────────────────────────────────────────────

    def freeze_backbone(self) -> None:
        """
        Freeze the input projection and all encoder layers.

        Call this after pretraining and before on-device GRPO fine-tuning so
        that only the projection head receives gradient updates.
        """
        for param in self.input_projection.parameters():
            param.requires_grad = False
        for param in self.encoder_layers.parameters():
            param.requires_grad = False

    def unfreeze_backbone(self) -> None:
        """Re-enable gradients on the backbone (e.g., for continued pretraining)."""
        for param in self.input_projection.parameters():
            param.requires_grad = True
        for param in self.encoder_layers.parameters():
            param.requires_grad = True

    def trainable_parameters(self) -> list:
        """
        Return only the projection head parameters.

        Used by the GRPO trainer to construct a parameter-group that excludes
        the frozen backbone.
        """
        return [
            {"params": self.projection.parameters(), "name": "projection_weight"},
            {"params": [self.output_bias], "name": "output_bias"},
        ]

    def count_parameters(self) -> dict:
        """Return total / trainable parameter counts for logging."""
        total = sum(p.numel() for p in self.parameters())
        trainable = sum(p.numel() for p in self.parameters() if p.requires_grad)
        return {"total": total, "trainable": trainable, "frozen": total - trainable}
