# Summary of Changes

## Overview

Five new source files were added under `src/` implementing the complete
pretraining pipeline for the on-device `PersonalityModel`.  No existing files
were modified.

---

## New Files

### `src/__init__.py`
Package marker with a one-line description of the module's purpose.

---

### `src/tokens.py`
**Purpose:** Loads and exposes the fixed 325-token personality vocabulary.

**Key exports:**
- `TOKENS` — `List[str]`, canonical order from `personality-tokens.json`.  Index == output dimension.
- `TOKEN_INDEX` — `Dict[str, int]` reverse lookup.
- `VOCAB_SIZE = 325` — hard-coded guard; the loader asserts the JSON contains exactly this many tokens.
- `load_tokens(path)` — raises `ValueError` if token count drifts from 325.

**Design note:** The token ordering is immutable. Any reordering invalidates
all trained weights and deployed models.

---

### `src/model.py`
**Purpose:** Defines the `PersonalityModel` PyTorch module.

**Architecture:**
```
(batch, 1536)
  └─ input_projection   Linear(1536 → 512)       ← frozen backbone
  └─ encoder            2× TransformerEncoderLayer ← frozen backbone
  └─ projection         Linear(512 → 325)          ← trainable head
  └─ output_bias        Parameter(325,)             ← trainable head
(batch, 325)  raw logits  →  sigmoid → token probabilities
```

**Hyperparameters:**
| Name | Value |
|------|-------|
| `EMBEDDING_DIM` | 1536 |
| `LATENT_DIM` | 512 |
| `NUM_HEADS` | 8 |
| `NUM_ENCODER_LAYERS` | 2 |
| `FFN_DIM` | 2048 |
| `VOCAB_SIZE` | 325 |

**Key methods:**
- `forward(x)` — returns raw logits; apply `torch.sigmoid` at inference time.
- `freeze_backbone()` / `unfreeze_backbone()` — toggle gradient flow through encoder + input projection.
- `trainable_parameters()` — returns only the projection head params for GRPO.
- `count_parameters()` — returns `{total, trainable, frozen}` for logging.

**Parameter count:** ~3.5 M total, ~170 K trainable (projection head only after freezing).

---

### `src/embeddings.py`
**Purpose:** Converts raw text strings to 1536-dim float32 vectors consumed by `PersonalityModel`.  Embedding generation is **not** part of the Core ML graph.

**Two backends:**

| Backend | Class | Trigger |
|---------|-------|---------|
| OpenAI `text-embedding-3-small` | `OpenAIEmbeddingBackend` | `OPENAI_API_KEY` env var set |
| Local HuggingFace encoder | `LocalEmbeddingBackend` | default / fallback |

**`LocalEmbeddingBackend`:**
- Default model: `sentence-transformers/all-MiniLM-L6-v2` (384-dim hidden).
- Mean-pools last hidden state over non-padding tokens; L2-normalizes the result.
- Attaches `EmbeddingProjector` (Linear 384 → 1536) to match `PersonalityModel` input contract.
- Encoder is always frozen; projector is trained alongside `PersonalityModel` during pretraining.

**`EmbeddingBackend.from_env()`** — factory that auto-selects the correct backend.

---

### `src/dataset.py`
**Purpose:** Loads `FuseAI/FuseChat-Mixture`, embeds samples, and generates soft target distributions over the 325 tokens.

**Pipeline:**
1. Stream `FuseChat-Mixture` (streaming mode avoids full download).
2. Extract human-turn text from each conversation (`extract_text`).
3. Embed all samples → `(N, 1536)` tensor.
4. Build personality token embeddings → `(325, 1536)`.
5. Compute cosine similarity matrix → `(N, 325)`.
6. Apply temperature-scaled softmax (`T = 0.07`) → soft label targets.
7. Cache `embeddings.pt` + `targets.pt` + `metadata.json` in `<output_dir>/cache/`.

**Caching:** Cache is invalidated if the embedding model name or personality-token hash changes.

**`PersonalityDataset`** — `torch.utils.data.Dataset` returning `{embedding, targets}` dicts.

---

### `src/train.py`
**Purpose:** Main pretraining script.  Runs for exactly **3 epochs** by default.

**Training configuration:**
| Setting | Value |
|---------|-------|
| Epochs | **3** |
| Batch size | 256 |
| Optimiser | AdamW (`lr=3e-4`, `wd=1e-2`) |
| LR schedule | Cosine annealing → `1e-6` |
| Loss | `BCEWithLogitsLoss` (multi-label, sigmoid fused) |
| Gradient clipping | L2 norm ≤ 1.0 |
| Validation split | 5% |

**Per-epoch outputs:**
- Console: step-level loss + top-5 recall every 50 steps; epoch summary.
- Disk: `checkpoints/epoch_<N>_valloss_<loss>.pt` — full checkpoint (model + optimiser + scheduler).

**Post-training outputs:**
- `outputs/personality_model_weights.pt` — deployment weights (no optimiser state).
- `outputs/training_history.json` — per-epoch metrics.
- `outputs/PersonalityModel.mlpackage` — Core ML bundle (if `export_coreml=True`).

**CLI usage:**
```bash
source trainer/bin/activate
python -m src.train \
  --output-dir outputs \
  --epochs 3 \
  --batch-size 256 \
  --lr 3e-4 \
  --local-model sentence-transformers/all-MiniLM-L6-v2 \
  --max-samples 50000
```

---

### `src/export.py`
**Purpose:** Exports the trained `PersonalityModel` to a Core ML `.mlpackage`.

**Export steps:**
1. Load `personality_model_weights.pt` and freeze backbone.
2. Trace with `torch.jit.trace` using a `(1, 1536)` dummy input.
3. Convert via `coremltools.convert` targeting iOS 17 / macOS 14 in **ML Program** format (`FLOAT32`).
4. Mark `projection` weight and `output_bias` as updatable parameters for on-device GRPO.
5. Attach metadata: token labels, vocab size, embedding dim.
6. Save `PersonalityModel.mlpackage`.

**Updatable parameters:** Only the projection head (`Linear(512→325)` + `output_bias`) is marked updatable.  The frozen backbone layers are excluded from on-device gradient updates.

**Inspection helper:** `inspect_mlpackage(path)` prints input/output specs and stored token metadata.

---

## Architecture Constraints Preserved

| Constraint | How enforced |
|-----------|--------------|
| Fixed 325-token ordering | `tokens.py` asserts count; tokens embedded in checkpoint and mlpackage metadata |
| No dynamic vocabulary | `VOCAB_SIZE` constant used throughout; no runtime resizing |
| Encoder frozen for on-device fine-tuning | `freeze_backbone()` called before export |
| Projection head updatable on device | `_mark_updatable_layers()` in `export.py` |
| Simple graph for Core ML ANE | `seq_len=1` transformer, `batch_first=True`, `enable_nested_tensor=False` |
| Embedding outside model boundary | `EmbeddingBackend` is a standalone class never included in the traced graph |
