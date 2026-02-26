"""
model.py
--------
Defines the PersonalityModel architecture.

Pipeline (all dimensions are explicit):
    Input  : (batch, 1536)  — pre-computed text embedding
    ↓ input_projection      — linear 1536→LATENT_DIM
    ↓ encoder               — N× TransformerEncoderLayer  (frozen backbone)
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

        # Standard transformer encoder. Each layer applies:
        #   multi-head self-attention → residual → layer-norm
        #   feed-forward (ReLU)      → residual → layer-norm
        #
        # batch_first=True means input shape is (batch, seq, dim), which is
        # required for clean Core ML export (static batch / seq dims).
        encoder_layer = nn.TransformerEncoderLayer(
            d_model=latent_dim,
            nhead=num_heads,
            dim_feedforward=ffn_dim,
            dropout=dropout,
            batch_first=True,
            norm_first=False,  # post-norm (standard); more stable for export
        )
        self.encoder = nn.TransformerEncoder(
            encoder_layer,
            num_layers=num_encoder_layers,
            enable_nested_tensor=False,  # disable for deterministic Core ML export
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
        h = self.encoder(h)  # (batch, 1, LATENT_DIM)

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
        for param in self.encoder.parameters():
            param.requires_grad = False

    def unfreeze_backbone(self) -> None:
        """Re-enable gradients on the backbone (e.g., for continued pretraining)."""
        for param in self.input_projection.parameters():
            param.requires_grad = True
        for param in self.encoder.parameters():
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
