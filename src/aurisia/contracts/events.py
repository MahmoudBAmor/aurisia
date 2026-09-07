"""In-process domain contracts.

The Protobuf schemas under ``contracts/proto`` are transport DTOs. These
immutable objects are the corresponding domain-facing contracts and contain no
model- or framework-specific types.
"""

from __future__ import annotations

from dataclasses import dataclass
from enum import Enum


class VoiceActivityState(str, Enum):
    SILENCE = "silence"
    SPEECH_START = "speech_start"
    SPEECH_CONTINUE = "speech_continue"
    SPEECH_END = "speech_end"


class Direction(str, Enum):
    UNKNOWN = "unknown"
    LEFT = "left"
    CENTER = "center"
    RIGHT = "right"


class Priority(str, Enum):
    INFORMATION = "information"
    CONVERSATION = "conversation"
    ATTENTION = "attention"
    VEHICLE = "vehicle"
    DANGER = "danger"


class PerceptionKind(str, Enum):
    SPEECH = "speech"
    SOUND = "sound"


@dataclass(frozen=True, slots=True)
class ModelDescriptor:
    model_id: str
    version: str
    runtime: str

    def __post_init__(self) -> None:
        if not self.model_id.strip():
            raise ValueError("model_id must not be empty")
        if not self.version.strip():
            raise ValueError("model version must not be empty")
        if not self.runtime.strip():
            raise ValueError("model runtime must not be empty")


@dataclass(frozen=True, slots=True)
class AudioFrame:
    stream_id: str
    sequence: int
    captured_at_ms: int
    sample_rate_hz: int
    channels: int
    pcm_s16le: bytes

    def __post_init__(self) -> None:
        if not self.stream_id:
            raise ValueError("stream_id must not be empty")
        if self.sequence < 0:
            raise ValueError("sequence must be non-negative")
        if self.captured_at_ms < 0:
            raise ValueError("captured_at_ms must be non-negative")
        if self.sample_rate_hz <= 0:
            raise ValueError("sample_rate_hz must be positive")
        if self.channels <= 0:
            raise ValueError("channels must be positive")
        sample_width = 2 * self.channels
        if not self.pcm_s16le or len(self.pcm_s16le) % sample_width:
            raise ValueError("pcm_s16le must contain complete interleaved 16-bit samples")

    @property
    def samples_per_channel(self) -> int:
        return len(self.pcm_s16le) // (2 * self.channels)

    @property
    def duration_ms(self) -> int:
        return round(self.samples_per_channel * 1000 / self.sample_rate_hz)

    @property
    def end_time_ms(self) -> int:
        return self.captured_at_ms + self.duration_ms


@dataclass(frozen=True, slots=True)
class VoiceActivity:
    stream_id: str
    frame_sequence: int
    state: VoiceActivityState
    probability: float
    observed_at_ms: int

    def __post_init__(self) -> None:
        if not 0.0 <= self.probability <= 1.0:
            raise ValueError("VAD probability must be in [0, 1]")


@dataclass(frozen=True, slots=True)
class SpeechSegment:
    segment_id: str
    stream_id: str
    start_time_ms: int
    end_time_ms: int
    sample_rate_hz: int
    channels: int
    pcm_s16le: bytes

    def __post_init__(self) -> None:
        if self.end_time_ms <= self.start_time_ms:
            raise ValueError("speech segment end must follow its start")
        if not self.pcm_s16le:
            raise ValueError("speech segment must contain audio")


@dataclass(frozen=True, slots=True)
class TranscriptEvent:
    event_id: str
    stream_id: str
    start_time_ms: int
    end_time_ms: int
    raw_text: str
    display_text: str
    locale: str
    confidence: float | None
    is_final: bool
    model: ModelDescriptor

    def __post_init__(self) -> None:
        if not self.raw_text.strip():
            raise ValueError("raw transcript must not be empty")
        if not self.display_text.strip():
            raise ValueError("display transcript must not be empty")
        _validate_optional_confidence(self.confidence)


@dataclass(frozen=True, slots=True)
class SoundEvent:
    event_id: str
    stream_id: str
    start_time_ms: int
    end_time_ms: int
    label: str
    display_label: str
    confidence: float | None
    model: ModelDescriptor

    def __post_init__(self) -> None:
        if not self.label.startswith("sound."):
            raise ValueError("sound labels must use the canonical 'sound.' namespace")
        if not self.display_label.strip():
            raise ValueError("display_label must not be empty")
        _validate_optional_confidence(self.confidence)


@dataclass(frozen=True, slots=True)
class DirectionEstimate:
    source_event_id: str
    direction: Direction
    angle_degrees: float | None
    confidence: float | None
    model: ModelDescriptor

    def __post_init__(self) -> None:
        if self.angle_degrees is not None and not -180.0 <= self.angle_degrees <= 180.0:
            raise ValueError("angle_degrees must be in [-180, 180]")
        _validate_optional_confidence(self.confidence)


@dataclass(frozen=True, slots=True)
class PerceptionEvent:
    event_id: str
    source_event_id: str
    kind: PerceptionKind
    title: str
    icon: str
    priority: Priority
    color: str
    direction: Direction
    start_time_ms: int
    end_time_ms: int
    lifetime_ms: int
    confidence: float | None

    def __post_init__(self) -> None:
        if not self.title.strip():
            raise ValueError("perception title must not be empty")
        if self.end_time_ms < self.start_time_ms:
            raise ValueError("perception event end must not precede start")
        if self.lifetime_ms <= 0:
            raise ValueError("perception event lifetime must be positive")
        _validate_optional_confidence(self.confidence)


def _validate_optional_confidence(value: float | None) -> None:
    if value is not None and not 0.0 <= value <= 1.0:
        raise ValueError("confidence must be in [0, 1] when supplied")
