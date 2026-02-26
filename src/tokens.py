"""
tokens.py
---------
Loads the fixed vocabulary of 325 personality tokens from personality-tokens.json.

The ordering of tokens is FIXED and must never change — every index maps to a
specific output dimension in the Core ML model. Changing order would invalidate
all pretrained weights and any deployed model.
"""

import json
from pathlib import Path
from typing import List, Dict

# Canonical path, relative to the project root.
DEFAULT_TOKEN_FILE = Path(__file__).parent.parent / "personality-tokens.json"

# Number of personality tokens. Hard-coded as a guard; the loader will assert
# this matches the JSON so mismatches are caught early.
VOCAB_SIZE: int = 325


def load_tokens(path: Path = DEFAULT_TOKEN_FILE) -> List[str]:
    """
    Load the personality token list from the JSON file.

    Returns a plain Python list of strings in canonical order.
    The list index == the model output dimension for that token.

    Raises:
        FileNotFoundError: if personality-tokens.json cannot be found.
        ValueError: if the token count does not equal VOCAB_SIZE.
    """
    path = Path(path)
    if not path.exists():
        raise FileNotFoundError(
            f"personality-tokens.json not found at {path}. "
            "Ensure you are running from the project root."
        )

    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)

    tokens: List[str] = data["tokens"]

    if len(tokens) != VOCAB_SIZE:
        raise ValueError(
            f"Expected {VOCAB_SIZE} tokens but found {len(tokens)} "
            f"in {path}. Do not modify personality-tokens.json."
        )

    return tokens


def build_token_index(tokens: List[str]) -> Dict[str, int]:
    """
    Build a {token_string: index} lookup dictionary.

    Useful for converting a token name back to its output dimension.
    """
    return {token: idx for idx, token in enumerate(tokens)}


# Module-level singletons — load once and reuse.
# Any module that needs the vocabulary imports these directly.
TOKENS: List[str] = load_tokens()
TOKEN_INDEX: Dict[str, int] = build_token_index(TOKENS)
