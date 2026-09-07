"""Offline Arabic-script display normalization for Tunisian transcripts."""

from __future__ import annotations

import re
from collections.abc import Mapping
from pathlib import Path

import yaml


class ArabicScriptNormalizer:
    """Normalize known code-switched phrases without inventing unknown words.

    The original ASR transcript is always retained in ``TranscriptEvent``.
    Unknown Latin terms are intentionally preserved: silent, guessed
    transliteration would be more harmful than a mixed-script token.
    """

    def __init__(self, replacements: Mapping[str, str]) -> None:
        cleaned = {
            source.strip(): target.strip()
            for source, target in replacements.items()
            if source.strip() and target.strip()
        }
        self._patterns = tuple(
            (
                re.compile(
                    rf"(?<![\w-]){re.escape(source)}(?![\w-])",
                    flags=re.IGNORECASE,
                ),
                target,
            )
            for source, target in sorted(
                cleaned.items(),
                key=lambda item: len(item[0]),
                reverse=True,
            )
        )

    @classmethod
    def from_yaml(cls, path: Path) -> ArabicScriptNormalizer:
        try:
            raw = yaml.safe_load(path.read_text(encoding="utf-8"))
        except OSError as exc:
            raise ValueError(f"cannot read Arabic lexicon {path}: {exc}") from exc
        except yaml.YAMLError as exc:
            raise ValueError(f"invalid Arabic lexicon {path}: {exc}") from exc
        if not isinstance(raw, dict) or set(raw) != {"schema_version", "replacements"}:
            raise ValueError("Arabic lexicon must contain schema_version and replacements")
        if raw["schema_version"] != 1:
            raise ValueError("unsupported Arabic lexicon schema version")
        replacements = raw["replacements"]
        if not isinstance(replacements, dict) or not all(
            isinstance(key, str) and isinstance(value, str) for key, value in replacements.items()
        ):
            raise ValueError("Arabic lexicon replacements must map strings to strings")
        return cls(replacements)

    def normalize(self, text: str) -> str:
        normalized = text
        for pattern, replacement in self._patterns:
            normalized = pattern.sub(replacement, normalized)
        return " ".join(normalized.split())
