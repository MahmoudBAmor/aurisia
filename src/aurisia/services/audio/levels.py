"""Audio-level diagnostics independent of capture and model runtimes."""

from __future__ import annotations

import math
import struct

from aurisia.contracts import AudioFrame


def rms_dbfs(frame: AudioFrame) -> float:
    """Return frame RMS in dBFS, with silence represented as negative infinity."""

    square_sum = 0.0
    sample_count = 0
    for (sample,) in struct.iter_unpack("<h", frame.pcm_s16le):
        square_sum += sample * sample
        sample_count += 1
    if sample_count == 0:
        raise ValueError("cannot calculate the level of an empty audio frame")
    rms = math.sqrt(square_sum / sample_count)
    if rms == 0.0:
        return -math.inf
    return 20.0 * math.log10(rms / 32_768.0)
