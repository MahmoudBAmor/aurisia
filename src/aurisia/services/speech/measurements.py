"""Model-neutral speech inference measurements."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class SpeechInferenceMeasurement:
    audio_duration_ms: int
    inference_latency_ms: float
    finalization_latency_ms: float | None = None

    @property
    def real_time_factor(self) -> float:
        if self.audio_duration_ms <= 0:
            return 0.0
        return self.inference_latency_ms / self.audio_duration_ms
