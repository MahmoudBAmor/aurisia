"""Simple energy VAD used only for deterministic development."""

from __future__ import annotations

import math
import struct

from aurisia.contracts import AudioFrame, ModelDescriptor


class EnergyVadEngine:
    """Estimate speech probability from RMS amplitude.

    This adapter establishes the model boundary and is intentionally replaced
    by a Silero ONNX adapter in the model-integration increment.
    """

    model = ModelDescriptor(
        model_id="development.energy-vad",
        version="1",
        runtime="python",
    )

    def __init__(self, *, rms_threshold: float = 2_500.0) -> None:
        if rms_threshold <= 0:
            raise ValueError("rms_threshold must be positive")
        self._rms_threshold = rms_threshold

    def speech_probability(self, frame: AudioFrame) -> float:
        square_sum = 0.0
        sample_count = 0
        for (sample,) in struct.iter_unpack("<h", frame.pcm_s16le):
            square_sum += sample * sample
            sample_count += 1
        rms = math.sqrt(square_sum / sample_count)
        return min(1.0, rms / self._rms_threshold)
