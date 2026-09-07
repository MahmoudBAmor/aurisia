"""Ports owned by the localization service."""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from aurisia.contracts import AudioFrame, Direction, ModelDescriptor


@dataclass(frozen=True, slots=True)
class LocalizationHypothesis:
    direction: Direction
    angle_degrees: float | None
    confidence: float | None


class LocalizationEngine(Protocol):
    @property
    def model(self) -> ModelDescriptor:
        """Describe the active direction model or simulator."""

        ...

    def observe(self, frame: AudioFrame) -> None:
        """Consume synchronized audio for a later temporal estimate."""

        ...

    def estimate(
        self,
        source_event_id: str,
        start_time_ms: int,
        end_time_ms: int,
    ) -> LocalizationHypothesis:
        """Estimate direction for the source event's time interval."""

        ...
