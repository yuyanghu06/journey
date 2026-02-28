#!/usr/bin/env python3
"""
convert_minilm_.py

Exports sentence-transformers/all-MiniLM-L6-v2 to two files:

    - all-MiniLM-L6-v2.mlpackage   CoreML model (iOS 16+, float16)
    - all-MiniLM-L6-v2-vocab.txt   Full WordPiece vocabulary (one token per line, ordered by id)

Default output directory: <repo_root>/outputs/output_folder/

Usage:
    python convert_minilm_.py
    python convert_minilm_.py --output-dir /path/to/dir
    python convert_minilm_.py --seq-len 256
"""

import argparse
import shutil
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
from transformers import AutoTokenizer, AutoModel
import coremltools as ct


# ── Constants ─────────────────────────────────────────────────────────────────

MODEL_ID    = "sentence-transformers/all-MiniLM-L6-v2"
MAX_SEQ_LEN = 128   # training max is 256; 128 covers ~99 % of real usage
EMBED_DIM   = 384


# ── Model wrapper ─────────────────────────────────────────────────────────────

class MiniLMEmbedder(nn.Module):
    """
    Wraps all-MiniLM-L6-v2 with mean-pooling + L2 normalisation so that
    CoreML sees a single (1, 384) float output.

    position_ids are stored as a fixed buffer so the tracer never encounters
    the dynamic integer-cast path inside BertEmbeddings, which CoreML cannot
    lower (TypeError: only 0-dimensional arrays can be converted to Python scalars).
    """

    def __init__(self, encoder: nn.Module, seq_len: int) -> None:
        super().__init__()
        self.encoder = encoder
        # Constant positional indices — avoids dynamic cumsum/int cast in tracer
        self.register_buffer(
            "position_ids",
            torch.arange(seq_len, dtype=torch.long).unsqueeze(0),  # (1, seq_len)
        )

    def forward(
        self,
        input_ids: torch.Tensor,        # (1, seq_len)  int64
        attention_mask: torch.Tensor,   # (1, seq_len)  int64
        token_type_ids: torch.Tensor,   # (1, seq_len)  int64
    ) -> torch.Tensor:                  # (1, 384)       float32

        # Pre-compute 4D additive float mask (shape: 1, 1, 1, seq_len).
        # BertModel._create_attention_masks → _preprocess_mask_arguments sees
        # ndim==4 and returns it as-is, completely bypassing the masking_utils
        # code that calls Tensor.new_ones() — which coremltools cannot lower.
        float_mask = attention_mask[:, None, None, :].float()   # (1,1,1,seq)
        additive_mask = (1.0 - float_mask) * -1e9               # 0 or -1e9

        outputs = self.encoder(
            input_ids=input_ids,
            attention_mask=additive_mask,       # 4-D → early-exit in mask utils
            token_type_ids=token_type_ids,
            position_ids=self.position_ids,
        )

        # Mean pooling — average over non-padding token positions
        token_embeddings = outputs.last_hidden_state          # (1, seq, 384)
        mask = attention_mask.unsqueeze(-1).float()           # (1, seq, 1)
        summed = (token_embeddings * mask).sum(dim=1)         # (1, 384)
        counts = mask.sum(dim=1).clamp(min=1e-9)              # (1, 1)
        mean_pooled = summed / counts                         # (1, 384)

        # L2 normalisation (unit-sphere)
        return nn.functional.normalize(mean_pooled, p=2, dim=1)


# ── Step 1 — load ─────────────────────────────────────────────────────────────

def load_model_and_tokenizer(model_id: str):
    print(f"Loading '{model_id}' from HuggingFace …")
    tokenizer = AutoTokenizer.from_pretrained(model_id)
    # attn_implementation="eager" forces the standard (non-SDPA) attention path,
    # which avoids new_ones / scaled_dot_product_attention ops that coremltools
    # cannot lower through its TorchScript → MIL frontend.
    hf_model = AutoModel.from_pretrained(model_id, attn_implementation="eager")
    hf_model.eval()
    return tokenizer, hf_model


# ── Step 2 — TorchScript trace ────────────────────────────────────────────────

def trace_model(
    hf_model: nn.Module,
    tokenizer,
    seq_len: int,
) -> tuple:
    """Return (traced_model, sample_encoding) for CoreML conversion."""
    print(f"Tracing model at seq_len={seq_len} …")
    wrapper = MiniLMEmbedder(hf_model, seq_len=seq_len)

    dummy = tokenizer(
        "The quick brown fox jumps over the lazy dog.",
        return_tensors="pt",
        max_length=seq_len,
        padding="max_length",
        truncation=True,
    )

    with torch.no_grad():
        traced = torch.jit.trace(
            wrapper,
            (dummy["input_ids"], dummy["attention_mask"], dummy["token_type_ids"]),
        )

    return traced, dummy


# ── Step 3 — CoreML conversion ────────────────────────────────────────────────

def convert_to_coreml(traced_model, sample_enc: dict, seq_len: int) -> ct.models.MLModel:
    """Convert a traced MiniLMEmbedder to a CoreML MLModel."""
    print("Converting to CoreML (float16, iOS 16+) …")

    inputs = [
        ct.TensorType(
            name="input_ids",
            shape=sample_enc["input_ids"].shape,
            dtype=np.int32,
        ),
        ct.TensorType(
            name="attention_mask",
            shape=sample_enc["attention_mask"].shape,
            dtype=np.int32,
        ),
        ct.TensorType(
            name="token_type_ids",
            shape=sample_enc["token_type_ids"].shape,
            dtype=np.int32,
        ),
    ]

    outputs = [
        ct.TensorType(name="embedding", dtype=np.float32),
    ]

    mlmodel = ct.convert(
        traced_model,
        inputs=inputs,
        outputs=outputs,
        minimum_deployment_target=ct.target.iOS16,
        compute_precision=ct.precision.FLOAT16,
    )

    # Embed metadata for downstream consumers
    mlmodel.short_description = (
        "all-MiniLM-L6-v2 sentence embedder — 384-dim L2-normalised output"
    )
    mlmodel.author  = "sentence-transformers / exported by convert_minilm_.py"
    mlmodel.license = "Apache-2.0"
    mlmodel.version = "1.0"
    mlmodel.user_defined_metadata.update(
        {
            "embedding_dim": str(EMBED_DIM),
            "max_seq_len":   str(seq_len),
            "pooling":       "mean",
            "normalisation": "L2",
            "hf_model_id":   MODEL_ID,
        }
    )

    return mlmodel


# ── Step 4 — vocabulary export ────────────────────────────────────────────────

def export_vocabulary(tokenizer, out_path: Path) -> None:
    """
    Write the complete WordPiece vocabulary to a plain-text file.
    Lines are ordered by token id (0, 1, 2, …) so line N corresponds to id N.
    """
    vocab: dict[str, int] = tokenizer.get_vocab()
    sorted_tokens = [tok for tok, _ in sorted(vocab.items(), key=lambda x: x[1])]

    out_path.write_text("\n".join(sorted_tokens) + "\n", encoding="utf-8")
    print(f"Vocabulary  ({len(sorted_tokens)} tokens)  →  {out_path}")


# ── Main ──────────────────────────────────────────────────────────────────────

def main() -> None:
    repo_root   = Path(__file__).resolve().parent.parent
    default_out = repo_root / "outputs" / "output_folder"

    parser = argparse.ArgumentParser(
        description="Export all-MiniLM-L6-v2 to CoreML (.mlpackage) + vocabulary (.txt).",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=default_out,
        metavar="DIR",
        help="Directory to write output files",
    )
    parser.add_argument(
        "--model-id",
        default=MODEL_ID,
        metavar="HF_MODEL_ID",
        help="HuggingFace model ID to load",
    )
    parser.add_argument(
        "--seq-len",
        type=int,
        default=MAX_SEQ_LEN,
        metavar="N",
        help="Fixed sequence length baked into the CoreML graph",
    )
    args = parser.parse_args()

    out_dir: Path = args.output_dir
    out_dir.mkdir(parents=True, exist_ok=True)

    mlpackage_path = out_dir / "all-MiniLM-L6-v2.mlpackage"
    vocab_path     = out_dir / "all-MiniLM-L6-v2-vocab.txt"

    # ── Load ──────────────────────────────────────────────────────────────────
    tokenizer, hf_model = load_model_and_tokenizer(args.model_id)

    # ── Vocabulary ────────────────────────────────────────────────────────────
    export_vocabulary(tokenizer, vocab_path)

    # ── Trace ─────────────────────────────────────────────────────────────────
    traced, sample_enc = trace_model(hf_model, tokenizer, seq_len=args.seq_len)

    # ── Convert ───────────────────────────────────────────────────────────────
    mlmodel = convert_to_coreml(traced, sample_enc, seq_len=args.seq_len)

    # ── Save ──────────────────────────────────────────────────────────────────
    if mlpackage_path.exists():
        shutil.rmtree(mlpackage_path)   # coremltools refuses to overwrite

    mlmodel.save(str(mlpackage_path))
    print(f"CoreML model                →  {mlpackage_path}")
    print("\nDone.")


if __name__ == "__main__":
    main()
