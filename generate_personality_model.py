import argparse
import coremltools as ct
import coremltools.models.neural_network as nn
import numpy as np

VOCAB_SIZE  = 325
INPUT_DIM   = 1536

def main(hidden_dim: int):
    H = hidden_dim

    builder = nn.NeuralNetworkBuilder(
        input_features=[("input", ct.models.datatypes.Array(INPUT_DIM))],
        output_features=[("output", ct.models.datatypes.Array(VOCAB_SIZE))],
        mode="classifier"
    )

    builder.add_inner_product(
        "fc1",
        w=(np.random.randn(H, INPUT_DIM).astype(np.float32) * 0.01),
        b=np.zeros(H, dtype=np.float32),
        input_channels=INPUT_DIM,
        output_channels=H,
        has_bias=True,
        input_name="input",
        output_name="h1"
    )
    builder.add_activation("relu1", non_linearity="RELU", input_name="h1", output_name="h1r")

    builder.add_inner_product(
        "fc2",
        w=(np.random.randn(H, H).astype(np.float32) * 0.01),
        b=np.zeros(H, dtype=np.float32),
        input_channels=H,
        output_channels=H,
        has_bias=True,
        input_name="h1r",
        output_name="h2"
    )
    builder.add_activation("relu2", non_linearity="RELU", input_name="h2", output_name="h2r")

    builder.add_inner_product(
        "fc3",
        w=(np.random.randn(VOCAB_SIZE, H).astype(np.float32) * 0.01),
        b=np.zeros(VOCAB_SIZE, dtype=np.float32),
        input_channels=H,
        output_channels=VOCAB_SIZE,
        has_bias=True,
        input_name="h2r",
        output_name="logits"
    )
    builder.add_softmax("softmax", input_name="logits", output_name="output")

    # Make layers updatable
    for layer in ["fc1", "fc2", "fc3"]:
        builder.make_updatable([layer])

    builder.set_categorical_cross_entropy_loss(name="loss", input="output")
    builder.set_adam_optimizer(ct.models.neural_network.AdamParams(lr=1e-4, batch=16))
    builder.set_epochs(10)

    model = ct.models.MLModel(builder.spec)
    model.save("PersonalityModelStock.mlpackage")
    print(f"Saved PersonalityModelStock.mlpackage (H={H})")

if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--hidden", type=int, default=4096)
    args = ap.parse_args()
    main(args.hidden)