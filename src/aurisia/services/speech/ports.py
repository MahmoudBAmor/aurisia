"""Ports owned by the speech recognition service."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol, runtime_checkable

from aurisia.contracts import ModelDescriptor, SpeechSegment


@dataclass(frozen=True, slots=True)
class SpeechHypothesis:
    text: str
    confidence: float | None


class SpeechEngine(Protocol):
    @property
    def model(self) -> ModelDescriptor:
        """Describe the active speech model."""

        ...

    def transcribe(self, segment: SpeechSegment, locale: str) -> SpeechHypothesis:
        """Transcribe a complete speech segment."""

        ...


class StreamingSpeechSession(Protocol):
    def accept_pcm(self, pcm_s16le: bytes) -> None:
        """Incrementally decode one ordered canonical PCM chunk."""

        ...

    def finish(self, audio_duration_ms: int) -> SpeechHypothesis:
        """Finalize an utterance after all of its audio was accepted."""

        ...


@runtime_checkable
class PreviewingSpeechSession(Protocol):
    def preview(self) -> SpeechHypothesis:
        """Return the best non-final hypothesis for accepted audio."""

        ...


@runtime_checkable
class StreamingSpeechEngine(Protocol):
    @property
    def model(self) -> ModelDescriptor:
        """Describe the active speech model."""

        ...

    def start_stream(
        self,
        locale: str,
        sample_rate_hz: int,
        channels: int,
    ) -> StreamingSpeechSession:
        """Create isolated decoder state for one utterance."""

        ...


class TextDisplayNormalizer(Protocol):
    def normalize(self, text: str) -> str:
        """Transform raw ASR text for presentation."""

        ...
