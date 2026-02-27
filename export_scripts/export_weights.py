"""
CLI helper to export existing PersonalityModel weights to Core ML (.mlpackage)
without rerunning training.
"""

import argparse
import sys
from pathlib import Path

# Ensure repository root is on sys.path for `src` imports.
REPO_ROOT = Path(__file__).resolve().parents[1]
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from src.export import COREML_PACKAGE_NAME, export_to_coreml


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Export saved PersonalityModel weights to Core ML (.mlpackage)."
    )
    parser.add_argument(
        "--weights",
        type=Path,
        default=REPO_ROOT / "outputs" / "personality_model_weights.pt",
        help="Path to weights file from training (default: outputs/personality_model_weights.pt).",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=REPO_ROOT / "outputs",
        help="Directory where the .mlpackage bundle will be written (default: outputs/).",
    )
    parser.add_argument(
        "--package-name",
        default=COREML_PACKAGE_NAME,
        help=f"Filename for the output package (default: {COREML_PACKAGE_NAME}).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    weights_path: Path = args.weights
    output_dir: Path = args.output_dir

    if not weights_path.exists():
        sys.exit(f"[export_cli] Weights not found: {weights_path}")

    try:
        output_path = export_to_coreml(
            weights_path=weights_path,
            output_dir=output_dir,
            package_name=args.package_name,
        )
    except RuntimeError as exc:
        sys.exit(f"[export_cli] Export failed: {exc}")

    print(f"[export_cli] Saved Core ML package → {output_path}")


if __name__ == "__main__":
    main()
