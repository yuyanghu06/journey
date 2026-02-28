"""
export.py
---------
Export the trained PersonalityModel to Core ML (.mlpackage).

Core ML export requirements (from architecture spec):
  • Inference runs fully on device.
  • The projection head ('logits' innerProduct, 325-dim output) is marked
    UPDATABLE so MLUpdateTask can modify it on device without re-exporting.
  • The backbone layers remain frozen (not updatable).
  • The graph uses Neural Network spec format — MLUpdateTask does NOT support
    ML Program format (mlprogram).
  • The token vocabulary ordering is fixed and embedded in model metadata.

Export approach:
  1. Load trained weights into PersonalityModel.
  2. Freeze backbone (only projection head remains trainable).
  3. Trace with torch.jit.trace using a (1, 1536) dummy input.
  4. Convert to Core ML using neuralnetwork format (NOT mlprogram).
     MLUpdateTask requires Neural Network spec; mlprogram causes CoreML Code=3.
  5. Add a softmax layer (logits → probabilities) for cross-entropy training.
  6. Mark the 'logits' innerProduct layer as isUpdatable=True.
  7. Set spec.isUpdatable=True, add label training input, loss layer, optimizer.
  8. Embed personality token labels in user metadata.
  9. Save the .mlpackage bundle.

Deployment target:
  iOS 13+ supports MLUpdateTask. iOS 17 is NOT required.
"""

import platform
from pathlib import Path
from typing import Tuple

import torch
import torch.nn as nn
import coremltools as ct
from coremltools.models.neural_network import NeuralNetworkBuilder
from coremltools.proto import FeatureTypes_pb2
from packaging.version import InvalidVersion, Version

from .model import EMBEDDING_DIM, LATENT_DIM, PersonalityModel
from .tokens import TOKENS, VOCAB_SIZE


# ── Constants ──────────────────────────────────────────────────────────────────

# Full inference model: backbone + stock head, dual output (latent + logits), NOT updatable.
COREML_PACKAGE_NAME: str = "PersonalityModelStock.mlpackage"

# Head-only updatable model: Linear(LATENT_DIM→VOCAB_SIZE), IS updatable via MLUpdateTask.
COREML_HEAD_PACKAGE_NAME: str = "PersonalityHeadUpdatable.mlpackage"

# iOS 13 is the minimum for MLUpdateTask (on-device training).
MIN_IOS_DEPLOYMENT_TARGET = ct.target.iOS13


# ── Wrapper modules for tracing ───────────────────────────────────────────────

class _PersonalityModelDual(nn.Module):
    """
    Full model with dual outputs: latent (LATENT_DIM) and logits (VOCAB_SIZE).
    NOT updatable. Used for inference AND for extracting backbone features for training.
    """
    def __init__(self, base: PersonalityModel) -> None:
        super().__init__()
        self._base = base

    def forward(self, x: torch.Tensor) -> Tuple[torch.Tensor, torch.Tensor]:
        h = self._base.input_projection(x)
        h = h.unsqueeze(1)
        for layer in self._base.encoder_layers:
            h = layer(h)
        latent = h.squeeze(1)                                    # (1, LATENT_DIM)
        logits = self._base.projection(latent) + self._base.output_bias  # (1, VOCAB_SIZE)
        return latent, logits


class _ProjectionHead(nn.Module):
    """
    Projection head only: Linear(LATENT_DIM→VOCAB_SIZE) + bias.
    No reshapes — safe for MLUpdateTask backward pass.
    Weights are shared with (copied from) the trained PersonalityModel.
    """
    def __init__(self, base: PersonalityModel) -> None:
        super().__init__()
        # Copy weights so this module owns them (avoids shared-parameter tracing issues).
        self._projection = nn.Linear(LATENT_DIM, VOCAB_SIZE, bias=False)
        self._projection.weight = nn.Parameter(base.projection.weight.detach().clone())
        self._output_bias = nn.Parameter(base.output_bias.detach().clone())

    def forward(self, x: torch.Tensor) -> torch.Tensor:  # x: (1, LATENT_DIM)
        return self._projection(x) + self._output_bias


# ── Main export function ───────────────────────────────────────────────────────

def export_to_coreml(
    weights_path: "str | Path",
    output_dir: "str | Path" = "outputs",
    package_name: str = COREML_PACKAGE_NAME,
    head_package_name: str = COREML_HEAD_PACKAGE_NAME,
) -> Tuple[Path, Path]:
    """
    Export both models needed for on-device personality inference + training.

    Returns:
        (full_model_path, head_model_path)

        PersonalityModelStock.mlpackage  — full inference model, dual output
                                           (latent 512-dim + logits 325-dim), NOT updatable.
        PersonalityHeadUpdatable.mlpackage — projection head only (Linear 512→325),
                                             IS updatable via MLUpdateTask. No attention
                                             layers → no reshape crashes during backprop.
    """
    _validate_coreml_environment()

    weights_path = Path(weights_path)
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"\n[export] Loading weights from {weights_path} ...")

    # ── Step 1: Load weights ───────────────────────────────────────────────────
    model = PersonalityModel()
    checkpoint = torch.load(weights_path, map_location="cpu")
    load_status = model.load_state_dict(checkpoint["model_state_dict"], strict=False)
    if load_status.missing_keys or load_status.unexpected_keys:
        raise RuntimeError(
            "[export] Checkpoint does not match current architecture. "
            "Retrain and export again to produce compatible weights."
        )
    model.freeze_backbone()
    model.eval()
    print("[export] Model loaded. Backbone frozen.")

    # ── Step 2: Export full inference model (dual output) ─────────────────────
    full_path = _export_full_model(model, output_dir, package_name)

    # ── Step 3: Export updatable head model ───────────────────────────────────
    head_path = _export_head_model(model, output_dir, head_package_name)

    return full_path, head_path


def _export_full_model(model: PersonalityModel, output_dir: Path, package_name: str) -> Path:
    """
    Export the full model with dual outputs: latent (LATENT_DIM) and logits (VOCAB_SIZE).
    This model is NOT updatable — used for inference and backbone feature extraction.

    Outputs:
        latent: (1, 512)  — backbone representation, fed to head model after training
        logits: (1, 325)  — stock head logits, used for inference before any training
    """
    import shutil
    output_path = output_dir / package_name
    dual_module = _PersonalityModelDual(model)
    dual_module.eval()

    example_input = torch.zeros(1, EMBEDDING_DIM)
    with torch.no_grad():
        traced = torch.jit.trace(dual_module, example_input)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="embedding", shape=(1, EMBEDDING_DIM), dtype=float)],
        outputs=[ct.TensorType(name="latent"), ct.TensorType(name="logits")],
        minimum_deployment_target=MIN_IOS_DEPLOYMENT_TARGET,
        convert_to="neuralnetwork",
    )
    print("[export] Full model (dual output) conversion complete.")

    mlmodel.short_description = (
        "Personality inference backbone. "
        "Outputs latent (512-dim) for head model and logits (325-dim) for direct inference."
    )
    mlmodel.input_description["embedding"] = "L2-normalised 1536-dim text embedding."
    mlmodel.output_description["latent"] = "512-dim backbone representation."
    mlmodel.output_description["logits"] = "325-dim raw logits (stock head weights)."
    mlmodel.user_defined_metadata["personality_tokens"] = ",".join(TOKENS)
    mlmodel.user_defined_metadata["vocab_size"] = str(VOCAB_SIZE)
    mlmodel.user_defined_metadata["embedding_dim"] = str(EMBEDDING_DIM)
    mlmodel.user_defined_metadata["latent_dim"] = str(LATENT_DIM)

    if output_path.exists():
        shutil.rmtree(str(output_path))
    mlmodel.save(str(output_path))
    print(f"[export] Saved full model → {output_path}")
    return output_path


def _export_head_model(model: PersonalityModel, output_dir: Path, package_name: str) -> Path:
    """
    Export the projection head only: Linear(LATENT_DIM→VOCAB_SIZE) + bias.

    This model IS updatable via MLUpdateTask. It has no attention layers and no
    reshape operations, so MLUpdateTask's backward pass works without crashing.

    Input:  latent (1, 512)  — from the full model's 'latent' output
    Output: logits (1, 325)

    Training inputs: latent + label (float32 one-hot vector, size 325)
    Loss: MSE(logits, label)
    Optimizer: Adam (lr=0.001, miniBatchSize=1)
    """
    import shutil
    output_path = output_dir / package_name
    head_module = _ProjectionHead(model)
    head_module.eval()

    example_latent = torch.zeros(1, LATENT_DIM)
    with torch.no_grad():
        traced = torch.jit.trace(head_module, example_latent)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="latent", shape=(1, LATENT_DIM), dtype=float)],
        outputs=[ct.TensorType(name="logits")],
        minimum_deployment_target=MIN_IOS_DEPLOYMENT_TARGET,
        convert_to="neuralnetwork",
    )
    print("[export] Head model conversion complete.")

    spec = mlmodel.get_spec()
    _configure_updatable_head_spec(spec)
    mlmodel = ct.models.MLModel(spec)

    mlmodel.short_description = (
        "Updatable personality projection head. "
        "Input: 512-dim latent from backbone. Output: 325-dim logits. "
        "Trained on-device via MLUpdateTask."
    )
    mlmodel.input_description["latent"] = "512-dim backbone latent representation."
    mlmodel.output_description["logits"] = "325-dim raw logits."
    mlmodel.user_defined_metadata["personality_tokens"] = ",".join(TOKENS)
    mlmodel.user_defined_metadata["vocab_size"] = str(VOCAB_SIZE)
    mlmodel.user_defined_metadata["latent_dim"] = str(LATENT_DIM)

    if output_path.exists():
        shutil.rmtree(str(output_path))
    mlmodel.save(str(output_path))
    print(f"[export] Saved updatable head → {output_path}")
    return output_path


def _configure_updatable_head_spec(spec) -> None:
    """
    Configure the head model spec for MLUpdateTask.

    The head model is just a single innerProduct (Linear 512→325).
    No attention, no reshapes — backprop works cleanly.
    """
    # Find the only innerProduct layer (there should be exactly one)
    head_layer = None
    for layer in spec.neuralNetwork.layers:
        if layer.WhichOneof("layer") == "innerProduct":
            if layer.innerProduct.outputChannels == VOCAB_SIZE:
                head_layer = layer
                break
    if head_layer is None:
        raise RuntimeError("[export] Could not find head innerProduct layer.")

    head_layer.isUpdatable = True
    head_layer.innerProduct.weights.isUpdatable = True
    if head_layer.innerProduct.hasBias:
        head_layer.innerProduct.bias.isUpdatable = True
    print(f"[export] Head layer '{head_layer.name}' marked updatable (outCh=325).")

    spec.isUpdatable = True

    # Training inputs: latent (main input) + label (target)
    latent_train = spec.description.trainingInput.add()
    latent_train.CopyFrom(spec.description.input[0])  # name="latent", shape=(1, 512)

    label_input = spec.description.trainingInput.add()
    label_input.name = "label"
    label_input.type.multiArrayType.dataType = FeatureTypes_pb2.ArrayFeatureType.FLOAT32
    label_input.type.multiArrayType.shape.append(VOCAB_SIZE)

    # MSE loss: logits vs one-hot float32 label
    loss_layer = spec.neuralNetwork.updateParams.lossLayers.add()
    loss_layer.name = "mse_loss"
    loss_layer.meanSquaredErrorLossLayer.input = "logits"
    loss_layer.meanSquaredErrorLossLayer.target = "label"

    # Adam optimizer — miniBatchSize=1 (head model has fixed batch=1 trace)
    adam = spec.neuralNetwork.updateParams.optimizer.adamOptimizer
    adam.learningRate.defaultValue = 0.001
    adam.learningRate.range.minValue = 1e-7
    adam.learningRate.range.maxValue = 1.0
    adam.beta1.defaultValue = 0.9
    adam.beta1.range.minValue = 0.0
    adam.beta1.range.maxValue = 1.0
    adam.beta2.defaultValue = 0.999
    adam.beta2.range.minValue = 0.0
    adam.beta2.range.maxValue = 1.0
    adam.eps.defaultValue = 1e-8
    adam.eps.range.minValue = 0.0
    adam.eps.range.maxValue = 1.0
    adam.miniBatchSize.defaultValue = 1
    adam.miniBatchSize.range.minValue = 1
    adam.miniBatchSize.range.maxValue = 1

    spec.neuralNetwork.updateParams.epochs.defaultValue = 5
    spec.neuralNetwork.updateParams.epochs.range.minValue = 1
    spec.neuralNetwork.updateParams.epochs.range.maxValue = 20


def _validate_coreml_environment() -> None:
    """
    Fail fast if coremltools cannot load platform-native extensions or if the
    runtime is an untested platform/version combination.
    """
    if platform.system() != "Darwin":
        raise RuntimeError(
            "[export] Core ML export requires macOS with the Apple-provided "
            "coremltools binaries. Run training with --no-export or perform "
            "export on a macOS machine."
        )

    try:
        import coremltools.libcoremlpython  # type: ignore
    except Exception as exc:  # pragma: no cover - environment dependent
        raise RuntimeError(
            "[export] coremltools native extensions are unavailable. Install "
            "coremltools via the official macOS wheel and ensure Xcode CLI "
            "tools are present."
        ) from exc

    try:
        torch_version = Version(torch.__version__.split("+")[0])
        tested = Version("2.7.0")
        if torch_version > tested:
            print(
                f"[export] Warning: Torch {torch.__version__} is newer than the "
                f"tested {tested}; conversion may be unstable."
            )
    except InvalidVersion:
        pass


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
