"""Ports owned by the environmental sound service."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Protocol

from aurisia.contracts import AudioFrame, ModelDescriptor


@dataclass(frozen=True, slots=True)
class SoundHypothesis:
    canonical_label: str
    confidence: float | None
    duration_ms: int


class SoundEngine(Protocol):
    @property
    def model(self) -> ModelDescriptor:
        """Describe the active environmental sound model."""

        ...

    def classify(self, frame: AudioFrame) -> Sequence[SoundHypothesis]:
        """Classify newly available audio and return completed events."""

        ...
