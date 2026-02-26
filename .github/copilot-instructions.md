

# Copilot Instructions — On‑Device Personality Model (Core ML)

## PRIMARY GOAL
Implement a small on‑device personality inference model exported to Core ML that outputs a probability distribution over a fixed vocabulary of **325 personality tokens** defined in `personality-tokens.json`.  
This model is used only to generate personality‑conditioning tokens that are appended to downstream LLM prompts.

The model must be:
- lightweight enough for on‑device inference
- exportable to `.mlpackage` / `.mlmodel`
- structured so that parts of the model (decoder / projection layers) can be fine‑tuned on device using GRPO

---

## HIGH‑LEVEL ARCHITECTURE

Pipeline:

1. **Input text → embedding vector**
   - Map input text to a **1536‑dimensional vector**.
   - This can be produced using a frozen embedding model (e.g. OpenAI embeddings or a local equivalent).
   - Embedding generation is NOT part of the Core ML personality model.

2. **Encoder block (frozen backbone)**
   - Input: 1536‑dim vector
   - Pass through one or more lightweight attention/transformer encoder layers
   - These layers should be treated as *mostly frozen* after export
   - Goal: produce a contextual latent representation

3. **Decoder / projection head (trainable on‑device)**
   - Final latent vector → linear projection → 325 logits
   - Apply sigmoid to obtain probability distribution over the token set
   - These projection weights MUST remain modifiable so GRPO can update them on device

Output:

```
1536‑dim input → encoder → latent → linear projection → 325‑dim token distribution
```

The 325‑dimensional space is **categorical**, not semantic.
Each dimension corresponds to exactly one predefined token.

---

## TRAINING PROCEDURE (OFF‑DEVICE PRETRAINING)

Dataset: `FuseAI/FuseChat-Mixture`

Training pipeline:

1. Chunk or pool text samples
2. Convert each chunk into a 1536‑dim embedding
3. Compute similarity between embedding and each personality token embedding
4. Convert similarities into a normalized target distribution over the 325 tokens
5. Train using BCEWithLogitsLoss (multi‑label token activation)

Important:
- The similarity step is used **only to create targets**
- The model itself never performs cosine search at inference time

Goal of pretraining:
- Learn a smooth mapping from semantic content → personality token activations

---

## ON‑DEVICE FINE‑TUNING REQUIREMENTS

The exported Core ML model must allow:

### Frozen components
- embedding input interface
- encoder / attention layers

### Trainable components
- final projection matrix (latent → 325)
- bias vector
- optional small adapter layers

These parameters must be accessible for GRPO updates.

GRPO training logic is implemented elsewhere; this file defines the model constraints required for it to function.

---

## EXPORT REQUIREMENTS

The model must be exportable to Core ML such that:

- inference runs fully on device
- projection weights can be replaced or updated
- the token vocabulary ordering is fixed and deterministic
- outputs map directly to indices in `personality-tokens.json`

No dynamic vocabulary resizing is allowed.

---

## WHAT THIS MODEL IS NOT

This model:
- is NOT a text generator
- is NOT a semantic embedding model
- is NOT a classifier over arbitrary labels

It is strictly a **token activation model** whose output is appended to prompts.

---

## COPILOT IMPLEMENTATION PRIORITIES

When generating code for this repository, Copilot should:

1. Preserve the fixed 325‑token ordering
2. Avoid introducing dynamic vocabularies
3. Keep encoder layers small and export‑friendly
4. Ensure projection weights are replaceable
5. Keep the Core ML graph simple and compatible with on‑device updates

If tradeoffs arise, prioritize:

1. Core ML compatibility
2. On‑device update capability
3. Small model size
4. Deterministic token mapping

Over architectural complexity.
