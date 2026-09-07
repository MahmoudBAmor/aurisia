"""Ports owned by the VAD service."""

from __future__ import annotations

from typing import Protocol

from aurisia.contracts import AudioFrame, ModelDescriptor


class VadEngine(Protocol):
    @property
    def model(self) -> ModelDescriptor:
        """Describe the active model implementation."""

        ...

    def speech_probability(self, frame: AudioFrame) -> float | None:
        """Return speech probability, or None while a model window is pending."""

        ...
