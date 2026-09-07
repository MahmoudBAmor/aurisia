"""PCM WAV replay adapter."""

from __future__ import annotations

import wave
from collections.abc import Iterator
from pathlib import Path

from aurisia.contracts import AudioFrame


class WaveFileAudioSource:
    """Replay an uncompressed 16-bit PCM WAV as timestamped frames.

    Replay is deliberately deterministic and does not sleep. A real-time clock
    is a transport concern and can be added by the caller.
    """

    def __init__(
        self,
        path: Path,
        *,
        frame_duration_ms: int = 20,
        stream_id: str | None = None,
    ) -> None:
        if frame_duration_ms <= 0:
            raise ValueError("frame_duration_ms must be positive")
        self._path = path
        self._frame_duration_ms = frame_duration_ms
        self._stream_id = stream_id or f"wav:{path.stem}"

    def frames(self) -> Iterator[AudioFrame]:
        try:
            with wave.open(str(self._path), "rb") as wav:
                if wav.getcomptype() != "NONE":
                    raise ValueError("only uncompressed PCM WAV files are supported")
                if wav.getsampwidth() != 2:
                    raise ValueError("only 16-bit PCM WAV files are supported")
                channels = wav.getnchannels()
                sample_rate_hz = wav.getframerate()
                frames_per_chunk = sample_rate_hz * self._frame_duration_ms // 1000
                if frames_per_chunk <= 0:
                    raise ValueError("frame duration is too short for the WAV sample rate")

                sequence = 0
                while pcm := wav.readframes(frames_per_chunk):
                    yield AudioFrame(
                        stream_id=self._stream_id,
                        sequence=sequence,
                        captured_at_ms=sequence * self._frame_duration_ms,
                        sample_rate_hz=sample_rate_hz,
                        channels=channels,
                        pcm_s16le=pcm,
                    )
                    sequence += 1
        except (OSError, wave.Error) as exc:
            raise ValueError(f"cannot open PCM WAV {self._path}: {exc}") from exc
