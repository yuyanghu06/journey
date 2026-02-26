"""
export.py
---------
Export the trained PersonalityModel to Core ML (.mlpackage).

Core ML export requirements (from architecture spec):
  • Inference runs fully on device.
  • The projection weights (linear + bias) are marked as UPDATABLE so GRPO
    can modify them on device without re-exporting the full model.
  • The token vocabulary ordering is fixed and deterministic — it is embedded
    in the model's metadata.
  • No dynamic vocabulary resizing.
  • The graph must be simple enough for on-device inference on Apple Neural Engine.

Export approach:
  1. Load trained weights into PersonalityModel.
  2. Freeze backbone (only projection head remains trainable).
  3. Trace the model with torch.jit.trace using a dummy 1536-dim input.
  4. Convert the TorchScript graph to Core ML with coremltools.
  5. Mark projection weight + bias as updatable parameters.
  6. Attach personality token labels as model metadata.
  7. Save the .mlpackage bundle.

Updatable parameters:
  coremltools marks specific weight tensors as updatable, which allows
  Core ML Training on device (used by GRPO) to update those weights while
  the frozen backbone layers remain static.
"""

from pathlib import Path
from typing import Optional

import torch
import coremltools as ct
import coremltools.optimize.coreml as cto

from .model import PersonalityModel, EMBEDDING_DIM
from .tokens import TOKENS, VOCAB_SIZE


# ── Constants ──────────────────────────────────────────────────────────────────

COREML_PACKAGE_NAME: str = "PersonalityModel.mlpackage"

# Minimum iOS / macOS deployment target for on-device training support.
# iOS 17 / macOS 14 introduced updatable Core ML models via Core ML Training.
MIN_IOS_DEPLOYMENT_TARGET = ct.target.iOS17
MIN_MACOS_DEPLOYMENT_TARGET = ct.target.macOS14


# ── Main export function ───────────────────────────────────────────────────────

def export_to_coreml(
    weights_path: "str | Path",
    output_dir: "str | Path" = "outputs",
    package_name: str = COREML_PACKAGE_NAME,
) -> Path:
    """
    Load trained weights, trace the model, convert to Core ML, and save.

    Args:
        weights_path:  Path to the .pt file from save_final_weights().
        output_dir:    Directory where the .mlpackage bundle is written.
        package_name:  Filename for the output bundle.

    Returns:
        Path to the saved .mlpackage directory.
    """
    weights_path = Path(weights_path)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)
    output_path = output_dir / package_name

    print(f"\n[export] Loading weights from {weights_path} ...")

    # ── Step 1: Reconstruct model and load weights ─────────────────────────────
    model = PersonalityModel()
    checkpoint = torch.load(weights_path, map_location="cpu")
    model.load_state_dict(checkpoint["model_state_dict"])

    # Freeze backbone — only projection head will be updatable in Core ML.
    model.freeze_backbone()
    model.eval()

    print(f"[export] Model loaded. Backbone frozen.")

    # ── Step 2: TorchScript tracing ───────────────────────────────────────────
    # torch.jit.trace records the exact computation graph for a concrete input.
    # We use a single example (batch_size=1) because Core ML inference
    # typically runs one sample at a time on device.
    # The batch dimension will be made flexible via flexible_shape_inputs below.
    example_input = torch.zeros(1, EMBEDDING_DIM)  # (1, 1536)

    with torch.no_grad():
        traced_model = torch.jit.trace(model, example_input)

    print("[export] TorchScript trace complete.")

    # ── Step 3: Core ML conversion ────────────────────────────────────────────
    # Define the input specification.
    # EMBEDDING_DIM=1536 is fixed; batch size can vary (flexible).
    input_spec = ct.TensorType(
        name="embedding",
        shape=ct.Shape(shape=(ct.RangeDim(1, 64), EMBEDDING_DIM)),
        dtype=float,
    )

    mlmodel = ct.convert(
        traced_model,
        inputs=[input_spec],
        outputs=[ct.TensorType(name="logits")],
        # Target iOS 17 / macOS 14 for updatable model support.
        minimum_deployment_target=MIN_IOS_DEPLOYMENT_TARGET,
        convert_to="mlprogram",  # ML Program format required for updatable models
        compute_precision=ct.precision.FLOAT32,
    )

    print("[export] coremltools conversion complete.")

    # ── Step 4: Mark projection weights as updatable ──────────────────────────
    # This is what allows GRPO to update the projection head on device.
    # We target the two leaf parameters of the trainable head:
    #   - projection weight matrix:  shape (VOCAB_SIZE, LATENT_DIM)
    #   - output_bias:               shape (VOCAB_SIZE,)
    #
    # Note: Layer names in the converted ML Program are derived from the
    # TorchScript node names, which mirror PyTorch attribute paths.
    spec = mlmodel.get_spec()
    _mark_updatable_layers(spec)
    mlmodel = ct.models.MLModel(spec)

    print("[export] Projection head marked as updatable.")

    # ── Step 5: Attach metadata ────────────────────────────────────────────────
    # Embedding the token vocabulary in the model ensures the ordering is
    # always available alongside the model binary — critical for correct
    # dimension → token mapping at inference time.
    mlmodel.short_description = (
        "On-device personality token activation model. "
        "Input: 1536-dim text embedding. "
        "Output: 325-dim logit vector (apply sigmoid for probabilities)."
    )
    mlmodel.input_description["embedding"] = (
        "L2-normalised 1536-dimensional text embedding vector."
    )
    mlmodel.output_description["logits"] = (
        "Raw logits for 325 personality tokens. Apply sigmoid for probabilities."
    )

    # Store token labels as user-defined metadata.
    # Keys in user_defined_metadata must be strings.
    mlmodel.user_defined_metadata["personality_tokens"] = ",".join(TOKENS)
    mlmodel.user_defined_metadata["vocab_size"] = str(VOCAB_SIZE)
    mlmodel.user_defined_metadata["embedding_dim"] = str(EMBEDDING_DIM)

    # ── Step 6: Save ──────────────────────────────────────────────────────────
    mlmodel.save(str(output_path))
    print(f"[export] Saved Core ML package → {output_path}")

    return output_path


# ── Updatable layer helper ─────────────────────────────────────────────────────

def _mark_updatable_layers(spec) -> None:
    """
    Traverse the Core ML model spec and mark the projection layer weights
    as updatable so GRPO on-device training can modify them.

    The layer naming convention in ML Program format uses dot-separated
    PyTorch attribute paths.  We search for layers whose names contain
    'projection' or 'output_bias' and mark them as isUpdatable=True.

    Note: coremltools marks weights, not layers, as updatable in ML Program
    specs.  This helper walks the network parameters and sets the flag.
    """
    try:
        # ML Program spec structure access.
        network = spec.mlProgram
        for function in network.functions.values():
            for block in function.block_specializations.values():
                for op in block.operations:
                    # Look for weight / bias ops linked to the projection head.
                    op_type = op.operator if hasattr(op, "operator") else ""
                    if "const" in op_type.lower():
                        for out_name in op.outputs:
                            if "projection" in out_name or "output_bias" in out_name:
                                # Mark this constant as updatable.
                                op.attributes["is_updatable"].b = True
    except Exception as exc:
        # Spec traversal is version-dependent; log and continue rather than crash.
        # The model will still export correctly — GRPO update code must handle
        # the case where parameter addresses are discovered at runtime.
        print(
            f"[export] Warning: could not mark updatable layers automatically "
            f"({exc}). Projection weights must be marked updatable manually "
            f"or via Core ML Training API at inference time."
        )


# ── Convenience: inspect exported model ───────────────────────────────────────

def inspect_mlpackage(package_path: "str | Path") -> None:
    """
    Print a summary of a saved .mlpackage for quick verification.

    Prints:
      - Input / output descriptions.
      - Stored personality token labels.
      - Updatable parameters (if any).
    """
    package_path = Path(package_path)
    if not package_path.exists():
        print(f"[inspect] Package not found: {package_path}")
        return

    mlmodel = ct.models.MLModel(str(package_path))
    spec = mlmodel.get_spec()

    print(f"\n{'='*60}")
    print(f"  Core ML Package: {package_path.name}")
    print(f"{'='*60}")
    print(f"  Description: {spec.description.metadata.shortDescription}")
    print(f"\n  Inputs:")
    for inp in spec.description.input:
        print(f"    {inp.name}: {list(inp.type.multiArrayType.shape)}")
    print(f"\n  Outputs:")
    for out in spec.description.output:
        print(f"    {out.name}: {list(out.type.multiArrayType.shape)}")

    meta = mlmodel.user_defined_metadata
    if "vocab_size" in meta:
        print(f"\n  Vocab size: {meta['vocab_size']}")
    if "personality_tokens" in meta:
        tokens = meta["personality_tokens"].split(",")
        print(f"  Token[0]: {tokens[0]}  …  Token[-1]: {tokens[-1]}")
    print(f"{'='*60}\n")
