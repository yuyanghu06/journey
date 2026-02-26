"""
train.py
--------
Pretraining script for the PersonalityModel.

Usage:
    python -m src.train [--output-dir outputs] [--epochs 3] [--batch-size 256]
                        [--lr 3e-4] [--local-model BAAI/bge-base-en-v1.5]
                        [--max-samples 50000] [--seed 42]

What this script does:
  1. Load personality tokens from personality-tokens.json.
  2. Initialise an embedding backend (OpenAI or local HuggingFace model).
  3. Build/load the PersonalityDataset — streams FuseChat-Mixture, embeds
     samples, and computes soft target distributions.
  4. Train PersonalityModel for --epochs epochs using BCEWithLogitsLoss.
  5. Save a checkpoint after each epoch and a final .pt weights file.
  6. Export the trained model to Core ML (.mlpackage) via export.py.

Loss function:
  BCEWithLogitsLoss is used because the task is multi-label activation —
  multiple personality tokens can and should be active for a given input.
  Sigmoid is applied internally by the loss; do NOT apply it in the forward
  pass during training.

Training is NOT run here; this file defines the logic only.
"""

import argparse
import json
import random
from pathlib import Path
from typing import Optional

import torch
import torch.nn as nn
from torch.utils.data import DataLoader, random_split
from torch.optim import AdamW
from torch.optim.lr_scheduler import CosineAnnealingLR

from .tokens import TOKENS, VOCAB_SIZE
from .model import PersonalityModel, EMBEDDING_DIM
from .embeddings import EmbeddingBackend, LocalEmbeddingBackend
from .dataset import PersonalityDataset


# ── Defaults / constants ───────────────────────────────────────────────────────

NUM_EPOCHS: int = 3                  # Pretraining epochs (fixed per spec)
BATCH_SIZE: int = 256                # Training batch size
LEARNING_RATE: float = 3e-4          # AdamW initial learning rate
WEIGHT_DECAY: float = 1e-2           # AdamW weight decay (regularisation)
VALIDATION_SPLIT: float = 0.05       # Fraction of data held out for validation
GRAD_CLIP_NORM: float = 1.0          # Max gradient L2 norm (prevents explosions)
LOG_EVERY_N_STEPS: int = 50          # Print training metrics every N steps
RANDOM_SEED: int = 42


# ── Reproducibility ────────────────────────────────────────────────────────────

def set_seed(seed: int) -> None:
    """Fix all random seeds for reproducible training runs."""
    random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
    if torch.backends.mps.is_available():
        torch.mps.manual_seed(seed)


# ── Device selection ───────────────────────────────────────────────────────────

def get_device() -> torch.device:
    """
    Select the best available compute device.

    Priority: CUDA GPU > Apple MPS (M-series) > CPU
    """
    if torch.cuda.is_available():
        return torch.device("cuda")
    if torch.backends.mps.is_available():
        return torch.device("mps")
    return torch.device("cpu")


# ── Training metrics ───────────────────────────────────────────────────────────

class RunningMetrics:
    """
    Lightweight accumulator for training metrics within an epoch.

    Tracks:
      - loss:         average BCEWithLogitsLoss over accumulated batches
      - top5_recall:  fraction of batches where ≥1 of the top-5 predicted tokens
                      matches a top-5 target token (proxy for activation quality)
    """

    def __init__(self) -> None:
        self.reset()

    def reset(self) -> None:
        self._loss_sum: float = 0.0
        self._top5_recall_sum: float = 0.0
        self._count: int = 0

    def update(
        self,
        loss: float,
        logits: torch.Tensor,
        targets: torch.Tensor,
    ) -> None:
        """
        Accumulate one batch of metrics.

        Args:
            loss:    Scalar loss value for the batch.
            logits:  (batch, 325) raw model output.
            targets: (batch, 325) soft labels.
        """
        self._loss_sum += loss
        self._count += 1

        # Top-5 recall: check if predicted top-5 overlaps with target top-5.
        with torch.no_grad():
            pred_top5 = logits.topk(5, dim=-1).indices   # (batch, 5)
            tgt_top5 = targets.topk(5, dim=-1).indices   # (batch, 5)
            # For each sample, check if any predicted token is in target top-5.
            recall = 0.0
            for p, t in zip(pred_top5, tgt_top5):
                hit = len(set(p.tolist()) & set(t.tolist())) > 0
                recall += float(hit)
            self._top5_recall_sum += recall / len(logits)

    @property
    def avg_loss(self) -> float:
        return self._loss_sum / max(self._count, 1)

    @property
    def avg_top5_recall(self) -> float:
        return self._top5_recall_sum / max(self._count, 1)


# ── Checkpoint helpers ─────────────────────────────────────────────────────────

def save_checkpoint(
    model: PersonalityModel,
    optimizer: AdamW,
    scheduler: CosineAnnealingLR,
    epoch: int,
    val_loss: float,
    output_dir: Path,
) -> Path:
    """
    Save a full training checkpoint (model + optimizer + scheduler state).

    Checkpoints allow resuming training if it is interrupted.

    File naming: epoch_<N>_valloss_<loss>.pt
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    checkpoint_path = output_dir / f"epoch_{epoch:02d}_valloss_{val_loss:.4f}.pt"
    torch.save(
        {
            "epoch": epoch,
            "model_state_dict": model.state_dict(),
            "optimizer_state_dict": optimizer.state_dict(),
            "scheduler_state_dict": scheduler.state_dict(),
            "val_loss": val_loss,
            "vocab_size": VOCAB_SIZE,
            "tokens": TOKENS,  # embed vocabulary ordering in checkpoint
        },
        checkpoint_path,
    )
    print(f"  [checkpoint] Saved → {checkpoint_path}")
    return checkpoint_path


def save_final_weights(model: PersonalityModel, output_dir: Path) -> Path:
    """
    Save only the model weights (no optimizer state) as a lightweight file
    suitable for deployment / Core ML export.
    """
    output_dir.mkdir(parents=True, exist_ok=True)
    weights_path = output_dir / "personality_model_weights.pt"
    torch.save(
        {
            "model_state_dict": model.state_dict(),
            "vocab_size": VOCAB_SIZE,
            "tokens": TOKENS,
            "embedding_dim": EMBEDDING_DIM,
        },
        weights_path,
    )
    print(f"  [weights] Saved → {weights_path}")
    return weights_path


# ── Single epoch helpers ───────────────────────────────────────────────────────

def train_one_epoch(
    model: PersonalityModel,
    loader: DataLoader,
    criterion: nn.BCEWithLogitsLoss,
    optimizer: AdamW,
    device: torch.device,
    epoch: int,
) -> RunningMetrics:
    """
    Run one full pass over the training DataLoader.

    Args:
        model:     PersonalityModel in training mode.
        loader:    DataLoader yielding {"embedding": ..., "targets": ...} batches.
        criterion: BCEWithLogitsLoss instance.
        optimizer: AdamW optimiser.
        device:    Target compute device.
        epoch:     Current epoch number (for logging).

    Returns:
        RunningMetrics with accumulated loss and top-5 recall.
    """
    model.train()
    metrics = RunningMetrics()

    for step, batch in enumerate(loader):
        # Move data to compute device.
        embeddings = batch["embedding"].to(device)  # (batch, 1536)
        targets = batch["targets"].to(device)        # (batch, 325)

        # ── Forward pass ───────────────────────────────────────────────────────
        logits = model(embeddings)  # (batch, 325) — raw logits, no sigmoid yet

        # BCEWithLogitsLoss applies sigmoid internally.
        # This is numerically more stable than sigmoid + BCELoss.
        loss = criterion(logits, targets)

        # ── Backward pass ──────────────────────────────────────────────────────
        optimizer.zero_grad()
        loss.backward()

        # Gradient clipping prevents instability from rare large gradients.
        torch.nn.utils.clip_grad_norm_(model.parameters(), GRAD_CLIP_NORM)

        optimizer.step()

        # ── Metrics accumulation ───────────────────────────────────────────────
        metrics.update(loss.item(), logits.detach(), targets.detach())

        # Periodic console logging.
        if (step + 1) % LOG_EVERY_N_STEPS == 0:
            print(
                f"  Epoch {epoch} | step {step + 1}/{len(loader)} | "
                f"loss {metrics.avg_loss:.4f} | "
                f"top5_recall {metrics.avg_top5_recall:.3f}"
            )

    return metrics


@torch.no_grad()
def validate(
    model: PersonalityModel,
    loader: DataLoader,
    criterion: nn.BCEWithLogitsLoss,
    device: torch.device,
) -> RunningMetrics:
    """
    Run a full pass over the validation DataLoader with gradients disabled.

    Args:
        model:     PersonalityModel switched to eval mode.
        loader:    Validation DataLoader.
        criterion: BCEWithLogitsLoss.
        device:    Compute device.

    Returns:
        RunningMetrics with validation loss and top-5 recall.
    """
    model.eval()
    metrics = RunningMetrics()

    for batch in loader:
        embeddings = batch["embedding"].to(device)
        targets = batch["targets"].to(device)

        logits = model(embeddings)
        loss = criterion(logits, targets)

        metrics.update(loss.item(), logits, targets)

    return metrics


# ── Main training loop ─────────────────────────────────────────────────────────

def train(
    output_dir: str = "outputs",
    epochs: int = NUM_EPOCHS,
    batch_size: int = BATCH_SIZE,
    learning_rate: float = LEARNING_RATE,
    local_model: str = "BAAI/bge-base-en-v1.5",
    max_samples: int = 50_000,
    seed: int = RANDOM_SEED,
    force_rebuild_cache: bool = False,
    export_coreml: bool = True,
) -> PersonalityModel:
    """
    Full pretraining pipeline.

    Steps:
      1. Set seeds, select device.
      2. Initialise embedding backend.
      3. Build (or load cached) PersonalityDataset.
      4. Split dataset into train / validation.
      5. Instantiate PersonalityModel + AdamW + cosine LR schedule.
      6. Run NUM_EPOCHS epochs of training + validation.
      7. Save checkpoint after each epoch.
      8. Save final weights.
      9. Export to Core ML if export_coreml=True.

    Args:
        output_dir:           Root directory for checkpoints and exports.
        epochs:               Number of training epochs (default 3).
        batch_size:           DataLoader batch size.
        learning_rate:        AdamW initial LR.
        local_model:          HuggingFace model ID for the local embedding backend.
        max_samples:          Max training samples from FuseChat-Mixture.
        seed:                 Random seed for reproducibility.
        force_rebuild_cache:  Ignore cached embeddings and recompute.
        export_coreml:        Export to .mlpackage after training.

    Returns:
        The trained PersonalityModel (on CPU, in eval mode).
    """
    set_seed(seed)
    device = get_device()
    output_path = Path(output_dir)
    checkpoint_dir = output_path / "checkpoints"

    print(f"[train] Device: {device}")
    print(f"[train] Output directory: {output_path.resolve()}")
    print(f"[train] Epochs: {epochs} | Batch size: {batch_size} | LR: {learning_rate}")
    print(f"[train] Vocab size: {VOCAB_SIZE} tokens")

    # ── Step 1: Embedding backend ──────────────────────────────────────────────
    # Auto-selects OpenAI if OPENAI_API_KEY is set, otherwise local model.
    embedding_backend = EmbeddingBackend.from_env(local_model=local_model)

    # ── Step 2: Dataset ────────────────────────────────────────────────────────
    dataset = PersonalityDataset(
        embedding_backend=embedding_backend,
        output_dir=output_path,
        max_samples=max_samples,
        force_rebuild=force_rebuild_cache,
    )
    print(f"[train] Dataset size: {len(dataset)} samples")

    # ── Step 3: Train / validation split ─────────────────────────────────────
    n_val = max(1, int(len(dataset) * VALIDATION_SPLIT))
    n_train = len(dataset) - n_val
    train_dataset, val_dataset = random_split(
        dataset,
        [n_train, n_val],
        generator=torch.Generator().manual_seed(seed),
    )
    print(f"[train] Train: {n_train} | Validation: {n_val}")

    train_loader = DataLoader(
        train_dataset,
        batch_size=batch_size,
        shuffle=True,
        num_workers=2,
        pin_memory=(device.type in ("cuda", "mps")),
        drop_last=False,
    )
    val_loader = DataLoader(
        val_dataset,
        batch_size=batch_size,
        shuffle=False,
        num_workers=2,
        pin_memory=(device.type in ("cuda", "mps")),
    )

    # ── Step 4: Model ──────────────────────────────────────────────────────────
    model = PersonalityModel().to(device)
    param_info = model.count_parameters()
    print(
        f"[train] Parameters — total: {param_info['total']:,} | "
        f"trainable: {param_info['trainable']:,}"
    )

    # ── Step 5: Loss, optimiser, scheduler ────────────────────────────────────
    # BCEWithLogitsLoss: numerically stable, appropriate for multi-label tasks.
    # reduction='mean' averages over all (batch × vocab_size) elements.
    criterion = nn.BCEWithLogitsLoss(reduction="mean")

    # AdamW: Adam with decoupled weight decay (better generalisation).
    optimizer = AdamW(
        model.parameters(),
        lr=learning_rate,
        weight_decay=WEIGHT_DECAY,
        betas=(0.9, 0.999),
    )

    # Cosine annealing: LR decays from learning_rate → 0 over total training steps.
    # This smooth decay typically improves final model quality.
    total_steps = epochs * len(train_loader)
    scheduler = CosineAnnealingLR(optimizer, T_max=total_steps, eta_min=1e-6)

    # ── Step 6: Training loop ──────────────────────────────────────────────────
    best_val_loss: float = float("inf")
    history = []  # per-epoch metric record for post-training analysis

    for epoch in range(1, epochs + 1):
        print(f"\n{'='*60}")
        print(f"  EPOCH {epoch} / {epochs}")
        print(f"{'='*60}")

        # ── Train ──────────────────────────────────────────────────────────────
        train_metrics = train_one_epoch(
            model, train_loader, criterion, optimizer, device, epoch
        )
        scheduler.step()  # update LR after each epoch

        # ── Validate ───────────────────────────────────────────────────────────
        val_metrics = validate(model, val_loader, criterion, device)

        # ── Log epoch summary ──────────────────────────────────────────────────
        current_lr = scheduler.get_last_lr()[0]
        print(
            f"\n  ── Epoch {epoch} summary ──\n"
            f"  train_loss     : {train_metrics.avg_loss:.4f}\n"
            f"  train_top5_rec : {train_metrics.avg_top5_recall:.3f}\n"
            f"  val_loss       : {val_metrics.avg_loss:.4f}\n"
            f"  val_top5_rec   : {val_metrics.avg_top5_recall:.3f}\n"
            f"  lr             : {current_lr:.2e}"
        )

        epoch_record = {
            "epoch": epoch,
            "train_loss": train_metrics.avg_loss,
            "train_top5_recall": train_metrics.avg_top5_recall,
            "val_loss": val_metrics.avg_loss,
            "val_top5_recall": val_metrics.avg_top5_recall,
            "lr": current_lr,
        }
        history.append(epoch_record)

        # ── Checkpoint ─────────────────────────────────────────────────────────
        save_checkpoint(
            model, optimizer, scheduler,
            epoch, val_metrics.avg_loss, checkpoint_dir
        )

        # Track best validation loss for final reporting.
        if val_metrics.avg_loss < best_val_loss:
            best_val_loss = val_metrics.avg_loss

    # ── Step 7: Save final weights ─────────────────────────────────────────────
    model.cpu()  # move to CPU before saving
    weights_path = save_final_weights(model, output_path)

    # Write training history to JSON for later analysis / plotting.
    history_path = output_path / "training_history.json"
    with open(history_path, "w") as fh:
        json.dump(history, fh, indent=2)
    print(f"\n[train] Training history → {history_path}")
    print(f"[train] Best validation loss: {best_val_loss:.4f}")

    # ── Step 8: Core ML export ─────────────────────────────────────────────────
    if export_coreml:
        # Import here to keep the training module independent of coremltools.
        from .export import export_to_coreml
        export_to_coreml(
            weights_path=weights_path,
            output_dir=output_path,
        )

    model.eval()
    return model


# ── CLI entry point ────────────────────────────────────────────────────────────

def _parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Pretrain the PersonalityModel on FuseChat-Mixture."
    )
    parser.add_argument(
        "--output-dir", default="outputs",
        help="Directory for checkpoints, cache, and exports (default: outputs/)."
    )
    parser.add_argument(
        "--epochs", type=int, default=NUM_EPOCHS,
        help=f"Training epochs (default: {NUM_EPOCHS})."
    )
    parser.add_argument(
        "--batch-size", type=int, default=BATCH_SIZE,
        help=f"Batch size (default: {BATCH_SIZE})."
    )
    parser.add_argument(
        "--lr", type=float, default=LEARNING_RATE,
        help=f"AdamW initial learning rate (default: {LEARNING_RATE})."
    )
    parser.add_argument(
        "--local-model", default="BAAI/bge-base-en-v1.5",
        help="HuggingFace model for local embeddings (default: BAAI/bge-base-en-v1.5)."
    )
    parser.add_argument(
        "--max-samples", type=int, default=50_000,
        help="Max training samples from FuseChat-Mixture (default: 50,000)."
    )
    parser.add_argument(
        "--seed", type=int, default=RANDOM_SEED,
        help=f"Random seed (default: {RANDOM_SEED})."
    )
    parser.add_argument(
        "--force-rebuild", action="store_true",
        help="Ignore embedding cache and recompute from scratch."
    )
    parser.add_argument(
        "--no-export", action="store_true",
        help="Skip Core ML export after training."
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = _parse_args()
    train(
        output_dir=args.output_dir,
        epochs=args.epochs,
        batch_size=args.batch_size,
        learning_rate=args.lr,
        local_model=args.local_model,
        max_samples=args.max_samples,
        seed=args.seed,
        force_rebuild_cache=args.force_rebuild,
        export_coreml=not args.no_export,
    )
