"""Environmental sound detection application service."""

from __future__ import annotations

from collections.abc import Mapping

from aurisia.contracts import AudioFrame, ModelDescriptor, SoundEvent

from .ports import SoundEngine


class SoundDetectionService:
    service_name = "sound_detection"

    def __init__(self, engine: SoundEngine, display_labels: Mapping[str, str]) -> None:
        self._engine = engine
        self._display_labels = dict(display_labels)

    @property
    def model(self) -> ModelDescriptor:
        return self._engine.model

    def observe(self, frame: AudioFrame) -> tuple[SoundEvent, ...]:
        events: list[SoundEvent] = []
        for index, hypothesis in enumerate(self._engine.classify(frame)):
            if hypothesis.canonical_label not in self._display_labels:
                raise ValueError(
                    f"no display label for canonical sound {hypothesis.canonical_label!r}"
                )
            events.append(
                SoundEvent(
                    event_id=(
                        f"sound:{frame.stream_id}:{frame.sequence}:"
                        f"{hypothesis.canonical_label}:{index}"
                    ),
                    stream_id=frame.stream_id,
                    start_time_ms=frame.captured_at_ms,
                    end_time_ms=frame.captured_at_ms + hypothesis.duration_ms,
                    label=hypothesis.canonical_label,
                    display_label=self._display_labels[hypothesis.canonical_label],
                    confidence=hypothesis.confidence,
                    model=self._engine.model,
                )
            )
        return tuple(events)
