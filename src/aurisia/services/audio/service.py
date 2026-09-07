"""Audio capture application service."""

from __future__ import annotations

from collections.abc import Iterator

from aurisia.contracts import AudioFrame

from .buffer import CircularAudioBuffer
from .ports import AudioSource


class AudioCaptureService:
    """Validate and expose an audio source as an ordered frame stream."""

    service_name = "audio_capture"

    def __init__(
        self,
        source: AudioSource,
        *,
        ring_buffer: CircularAudioBuffer | None = None,
    ) -> None:
        self._source = source
        self._ring_buffer = ring_buffer

    @property
    def ring_buffer(self) -> CircularAudioBuffer | None:
        return self._ring_buffer

    def stream(self) -> Iterator[AudioFrame]:
        previous_sequence = -1
        previous_timestamp = -1
        stream_id: str | None = None
        for frame in self._source.frames():
            if stream_id is None:
                stream_id = frame.stream_id
            elif frame.stream_id != stream_id:
                raise ValueError("an audio source must not change stream_id mid-stream")
            if frame.sequence <= previous_sequence:
                raise ValueError("audio frame sequences must be strictly increasing")
            if frame.captured_at_ms < previous_timestamp:
                raise ValueError("audio timestamps must be monotonic")
            previous_sequence = frame.sequence
            previous_timestamp = frame.captured_at_ms
            if self._ring_buffer is not None:
                self._ring_buffer.append(frame)
            yield frame
