# Encoding Model

**Goal**: Produce a **stable on-device** text embedding that ultimately becomes a **1536‑d** vector consumed by `PersonalityModel`.

## Base embedder (on device)
- **Model**: `sentence-transformers/all-MiniLM-L6-v2`
- **Output**: sentence embedding of shape `(batch, 384)` (float32)
- **Pooling**: mean pooling over token embeddings (as used by the Sentence-Transformers model)
- **Normalization**: L2-normalize the 384‑d embedding prior to projection

> Note: The encoding model is treated as part of the system contract. Do not swap embedding models without retraining downstream components.

## Projection to 1536
To match the `PersonalityModel` input contract, project the normalized 384‑d embedding to 1536:

\[
 z = \mathrm{LN}(e) \\ 
 x = W_{proj} z + b_{proj}
\]

- `e ∈ R^{384}`: MiniLM embedding (after pooling)
- `z ∈ R^{384}`: optional LayerNorm (recommended for stability)
- `W_proj ∈ R^{1536×384}`, `b_proj ∈ R^{1536}`
- `x ∈ R^{1536}`: final embedding passed to `PersonalityModel`

**Recommended post-projection normalization**:
- L2-normalize `x` before feeding it to `PersonalityModel` (keeps the input distribution stable across devices / OS versions).

## Export / implementation notes (iOS)
- Prefer converting the MiniLM encoder + projection into a single Core ML graph (or ship them as two Core ML models and run them sequentially).
- Quantization: consider 8‑bit weight quantization for the encoder for speed/size; keep projection in float16/float32 if needed for stability.
- Version the encoder + projection together (e.g., `encoder_v1`) to ensure the downstream `PersonalityModel` always sees the same embedding space.


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
