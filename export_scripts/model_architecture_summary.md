# PersonalityModel architecture (export target)

**Purpose**: Map a 1536‑d text embedding to 325 personality-token logits for on-device prompt conditioning. Outputs raw logits; apply sigmoid for probabilities.

## Inputs
- Tensor: shape `(batch, 1536)`, float32; batch is flexible (export uses range 1–64).
- Embeddings are assumed precomputed and L2-normalized; embedding model is **not** part of this graph.

## Backbone (frozen after pretraining)
1) **input_projection**: Linear `1536 → 512`, bias=True.  
2) **encoder_layers** (2 × identical blocks):
   - LayerNorm(512)
   - Multi-head self-attention: 8 heads, head_dim=64  
     - q/k/v projections: Linear `512 → 512` each  
     - attention: softmax(q·kᵀ / sqrt(64)), dropout=0.1  
     - out projection: Linear `512 → 512`, dropout=0.1
   - Residual add
   - LayerNorm(512)
   - Feed-forward: Linear `512 → 2048` → GELU → dropout=0.1 → Linear `2048 → 512` → dropout=0.1
   - Residual add

## Trainable head (updatable on device)
- **projection**: Linear `512 → 325`, bias=False  
- **output_bias**: Parameter `(325,)` added to projection output  
- Only these parameters are marked updatable in the Core ML export.

## Output
- Tensor `(batch, 325)` logits aligned to the fixed ordering in `personality-tokens.json`. Apply `sigmoid` to obtain activation probabilities.

## Core ML export notes
- Export format: ML Program (`.mlpackage`), minimum target iOS 17 / macOS 14.
- Updatable parameters: `projection.weight`, `output_bias`.
- Metadata includes: token list (comma-joined), `vocab_size=325`, `embedding_dim=1536`.
- Conversion expects macOS with coremltools native extensions available.
