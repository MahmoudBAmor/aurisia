"""Deterministic audio source for local development and end-to-end tests."""

from __future__ import annotations

import struct
from collections.abc import Iterable, Iterator

from aurisia.contracts import AudioFrame


class SyntheticAudioSource:
    """Generate PCM frames from a sequence of signed 16-bit amplitudes."""

    def __init__(
        self,
        amplitudes: Iterable[int],
        *,
        stream_id: str = "demo-stream",
        sample_rate_hz: int = 16_000,
        frame_duration_ms: int = 20,
    ) -> None:
        if sample_rate_hz <= 0:
            raise ValueError("sample_rate_hz must be positive")
        if frame_duration_ms <= 0:
            raise ValueError("frame_duration_ms must be positive")
        samples_per_frame = sample_rate_hz * frame_duration_ms // 1000
        if samples_per_frame <= 0:
            raise ValueError("frame duration is too short for the selected sample rate")
        self._amplitudes = tuple(amplitudes)
        if not all(-32_768 <= amplitude <= 32_767 for amplitude in self._amplitudes):
            raise ValueError("synthetic amplitudes must fit signed 16-bit PCM")
        self._stream_id = stream_id
        self._sample_rate_hz = sample_rate_hz
        self._frame_duration_ms = frame_duration_ms
        self._samples_per_frame = samples_per_frame

    @classmethod
    def demo_scenario(cls) -> SyntheticAudioSource:
        """Create silence, one speech segment, then a later sound window."""

        amplitudes = [0] * 10 + [4_500] * 30 + [0] * 20 + [1_000] * 30 + [0] * 10
        return cls(amplitudes)

    def frames(self) -> Iterator[AudioFrame]:
        for sequence, amplitude in enumerate(self._amplitudes):
            pcm = struct.pack(
                f"<{self._samples_per_frame}h",
                *([amplitude] * self._samples_per_frame),
            )
            yield AudioFrame(
                stream_id=self._stream_id,
                sequence=sequence,
                captured_at_ms=sequence * self._frame_duration_ms,
                sample_rate_hz=self._sample_rate_hz,
                channels=1,
                pcm_s16le=pcm,
            )
