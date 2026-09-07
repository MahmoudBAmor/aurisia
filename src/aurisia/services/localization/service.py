"""Direction estimation application service."""

from __future__ import annotations

from aurisia.contracts import (
    AudioFrame,
    DirectionEstimate,
    ModelDescriptor,
    SoundEvent,
    TranscriptEvent,
)

from .ports import LocalizationEngine


class LocalizationService:
    service_name = "localization"

    def __init__(self, engine: LocalizationEngine) -> None:
        self._engine = engine

    @property
    def model(self) -> ModelDescriptor:
        return self._engine.model

    def observe(self, frame: AudioFrame) -> None:
        self._engine.observe(frame)

    def estimate(self, event: TranscriptEvent | SoundEvent) -> DirectionEstimate:
        hypothesis = self._engine.estimate(
            event.event_id,
            event.start_time_ms,
            event.end_time_ms,
        )
        return DirectionEstimate(
            source_event_id=event.event_id,
            direction=hypothesis.direction,
            angle_degrees=hypothesis.angle_degrees,
            confidence=hypothesis.confidence,
            model=self._engine.model,
        )
