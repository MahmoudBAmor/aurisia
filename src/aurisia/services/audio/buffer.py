"""Thread-safe bounded circular audio buffer."""

from __future__ import annotations

from collections import deque
from threading import Lock

from aurisia.contracts import AudioFrame


class CircularAudioBuffer:
    """Retain only the most recent frames for segmentation and diagnostics."""

    def __init__(self, capacity_frames: int) -> None:
        if capacity_frames <= 0:
            raise ValueError("capacity_frames must be positive")
        self._frames: deque[AudioFrame] = deque(maxlen=capacity_frames)
        self._lock = Lock()

    @property
    def capacity_frames(self) -> int:
        max_length = self._frames.maxlen
        if max_length is None:  # pragma: no cover - deque is always bounded here
            raise RuntimeError("audio buffer unexpectedly has no capacity")
        return max_length

    def append(self, frame: AudioFrame) -> None:
        with self._lock:
            self._frames.append(frame)

    def snapshot(self) -> tuple[AudioFrame, ...]:
        with self._lock:
            return tuple(self._frames)

    def clear(self) -> None:
        with self._lock:
            self._frames.clear()
