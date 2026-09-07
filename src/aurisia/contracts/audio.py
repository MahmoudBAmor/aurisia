"""Audio device and diagnostic contracts."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True, slots=True)
class AudioDevice:
    id: str
    name: str
    host_api: str
    max_input_channels: int
    default_sample_rate_hz: float
    is_default: bool

    def __post_init__(self) -> None:
        if not self.id:
            raise ValueError("audio device id must not be empty")
        if not self.name:
            raise ValueError("audio device name must not be empty")
        if self.max_input_channels <= 0:
            raise ValueError("input device must expose at least one channel")
        if self.default_sample_rate_hz <= 0:
            raise ValueError("default sample rate must be positive")


@dataclass(frozen=True, slots=True)
class AudioMetrics:
    frames_captured: int
    frames_dropped: int
    callback_warnings: int
    reconnect_attempts: int
    last_error: str | None

    def __post_init__(self) -> None:
        if (
            min(
                self.frames_captured,
                self.frames_dropped,
                self.callback_warnings,
                self.reconnect_attempts,
            )
            < 0
        ):
            raise ValueError("audio metric counters must be non-negative")
