"""Stable, implementation-neutral contracts shared by Aurisia services."""

from .audio import AudioDevice, AudioMetrics
from .events import (
    AudioFrame,
    Direction,
    DirectionEstimate,
    ModelDescriptor,
    PerceptionEvent,
    PerceptionKind,
    Priority,
    SoundEvent,
    SpeechSegment,
    TranscriptEvent,
    VoiceActivity,
    VoiceActivityState,
)
from .serialization import to_primitive

__all__ = [
    "AudioFrame",
    "AudioDevice",
    "AudioMetrics",
    "Direction",
    "DirectionEstimate",
    "ModelDescriptor",
    "PerceptionEvent",
    "PerceptionKind",
    "Priority",
    "SoundEvent",
    "SpeechSegment",
    "TranscriptEvent",
    "VoiceActivity",
    "VoiceActivityState",
    "to_primitive",
]
