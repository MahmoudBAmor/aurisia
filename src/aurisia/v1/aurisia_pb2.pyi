from google.protobuf.internal import containers as _containers
from google.protobuf.internal import enum_type_wrapper as _enum_type_wrapper
from google.protobuf import descriptor as _descriptor
from google.protobuf import message as _message
from collections.abc import Iterable as _Iterable, Mapping as _Mapping
from typing import ClassVar as _ClassVar, Optional as _Optional, Union as _Union

DESCRIPTOR: _descriptor.FileDescriptor

class VoiceActivityState(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    VOICE_ACTIVITY_STATE_UNSPECIFIED: _ClassVar[VoiceActivityState]
    VOICE_ACTIVITY_STATE_SILENCE: _ClassVar[VoiceActivityState]
    VOICE_ACTIVITY_STATE_SPEECH_START: _ClassVar[VoiceActivityState]
    VOICE_ACTIVITY_STATE_SPEECH_CONTINUE: _ClassVar[VoiceActivityState]
    VOICE_ACTIVITY_STATE_SPEECH_END: _ClassVar[VoiceActivityState]

class Direction(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    DIRECTION_UNSPECIFIED: _ClassVar[Direction]
    DIRECTION_UNKNOWN: _ClassVar[Direction]
    DIRECTION_LEFT: _ClassVar[Direction]
    DIRECTION_CENTER: _ClassVar[Direction]
    DIRECTION_RIGHT: _ClassVar[Direction]

class Priority(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    PRIORITY_UNSPECIFIED: _ClassVar[Priority]
    PRIORITY_INFORMATION: _ClassVar[Priority]
    PRIORITY_CONVERSATION: _ClassVar[Priority]
    PRIORITY_ATTENTION: _ClassVar[Priority]
    PRIORITY_VEHICLE: _ClassVar[Priority]
    PRIORITY_DANGER: _ClassVar[Priority]

class PerceptionKind(int, metaclass=_enum_type_wrapper.EnumTypeWrapper):
    __slots__ = ()
    PERCEPTION_KIND_UNSPECIFIED: _ClassVar[PerceptionKind]
    PERCEPTION_KIND_SPEECH: _ClassVar[PerceptionKind]
    PERCEPTION_KIND_SOUND: _ClassVar[PerceptionKind]
VOICE_ACTIVITY_STATE_UNSPECIFIED: VoiceActivityState
VOICE_ACTIVITY_STATE_SILENCE: VoiceActivityState
VOICE_ACTIVITY_STATE_SPEECH_START: VoiceActivityState
VOICE_ACTIVITY_STATE_SPEECH_CONTINUE: VoiceActivityState
VOICE_ACTIVITY_STATE_SPEECH_END: VoiceActivityState
DIRECTION_UNSPECIFIED: Direction
DIRECTION_UNKNOWN: Direction
DIRECTION_LEFT: Direction
DIRECTION_CENTER: Direction
DIRECTION_RIGHT: Direction
PRIORITY_UNSPECIFIED: Priority
PRIORITY_INFORMATION: Priority
PRIORITY_CONVERSATION: Priority
PRIORITY_ATTENTION: Priority
PRIORITY_VEHICLE: Priority
PRIORITY_DANGER: Priority
PERCEPTION_KIND_UNSPECIFIED: PerceptionKind
PERCEPTION_KIND_SPEECH: PerceptionKind
PERCEPTION_KIND_SOUND: PerceptionKind

class ModelDescriptor(_message.Message):
    __slots__ = ("model_id", "version", "runtime")
    MODEL_ID_FIELD_NUMBER: _ClassVar[int]
    VERSION_FIELD_NUMBER: _ClassVar[int]
    RUNTIME_FIELD_NUMBER: _ClassVar[int]
    model_id: str
    version: str
    runtime: str
    def __init__(self, model_id: _Optional[str] = ..., version: _Optional[str] = ..., runtime: _Optional[str] = ...) -> None: ...

class AudioFrame(_message.Message):
    __slots__ = ("stream_id", "sequence", "captured_at_ms", "sample_rate_hz", "channels", "pcm_s16le")
    STREAM_ID_FIELD_NUMBER: _ClassVar[int]
    SEQUENCE_FIELD_NUMBER: _ClassVar[int]
    CAPTURED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    PCM_S16LE_FIELD_NUMBER: _ClassVar[int]
    stream_id: str
    sequence: int
    captured_at_ms: int
    sample_rate_hz: int
    channels: int
    pcm_s16le: bytes
    def __init__(self, stream_id: _Optional[str] = ..., sequence: _Optional[int] = ..., captured_at_ms: _Optional[int] = ..., sample_rate_hz: _Optional[int] = ..., channels: _Optional[int] = ..., pcm_s16le: _Optional[bytes] = ...) -> None: ...

class VoiceActivity(_message.Message):
    __slots__ = ("stream_id", "frame_sequence", "state", "probability", "observed_at_ms")
    STREAM_ID_FIELD_NUMBER: _ClassVar[int]
    FRAME_SEQUENCE_FIELD_NUMBER: _ClassVar[int]
    STATE_FIELD_NUMBER: _ClassVar[int]
    PROBABILITY_FIELD_NUMBER: _ClassVar[int]
    OBSERVED_AT_MS_FIELD_NUMBER: _ClassVar[int]
    stream_id: str
    frame_sequence: int
    state: VoiceActivityState
    probability: float
    observed_at_ms: int
    def __init__(self, stream_id: _Optional[str] = ..., frame_sequence: _Optional[int] = ..., state: _Optional[_Union[VoiceActivityState, str]] = ..., probability: _Optional[float] = ..., observed_at_ms: _Optional[int] = ...) -> None: ...

class SpeechSegment(_message.Message):
    __slots__ = ("segment_id", "stream_id", "start_time_ms", "end_time_ms", "sample_rate_hz", "channels", "pcm_s16le")
    SEGMENT_ID_FIELD_NUMBER: _ClassVar[int]
    STREAM_ID_FIELD_NUMBER: _ClassVar[int]
    START_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    END_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    PCM_S16LE_FIELD_NUMBER: _ClassVar[int]
    segment_id: str
    stream_id: str
    start_time_ms: int
    end_time_ms: int
    sample_rate_hz: int
    channels: int
    pcm_s16le: bytes
    def __init__(self, segment_id: _Optional[str] = ..., stream_id: _Optional[str] = ..., start_time_ms: _Optional[int] = ..., end_time_ms: _Optional[int] = ..., sample_rate_hz: _Optional[int] = ..., channels: _Optional[int] = ..., pcm_s16le: _Optional[bytes] = ...) -> None: ...

class TranscriptEvent(_message.Message):
    __slots__ = ("event_id", "stream_id", "start_time_ms", "end_time_ms", "raw_text", "display_text", "locale", "confidence", "is_final", "model")
    EVENT_ID_FIELD_NUMBER: _ClassVar[int]
    STREAM_ID_FIELD_NUMBER: _ClassVar[int]
    START_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    END_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    RAW_TEXT_FIELD_NUMBER: _ClassVar[int]
    DISPLAY_TEXT_FIELD_NUMBER: _ClassVar[int]
    LOCALE_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    IS_FINAL_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    event_id: str
    stream_id: str
    start_time_ms: int
    end_time_ms: int
    raw_text: str
    display_text: str
    locale: str
    confidence: float
    is_final: bool
    model: ModelDescriptor
    def __init__(self, event_id: _Optional[str] = ..., stream_id: _Optional[str] = ..., start_time_ms: _Optional[int] = ..., end_time_ms: _Optional[int] = ..., raw_text: _Optional[str] = ..., display_text: _Optional[str] = ..., locale: _Optional[str] = ..., confidence: _Optional[float] = ..., is_final: _Optional[bool] = ..., model: _Optional[_Union[ModelDescriptor, _Mapping]] = ...) -> None: ...

class SoundEvent(_message.Message):
    __slots__ = ("event_id", "stream_id", "start_time_ms", "end_time_ms", "label", "display_label", "confidence", "model")
    EVENT_ID_FIELD_NUMBER: _ClassVar[int]
    STREAM_ID_FIELD_NUMBER: _ClassVar[int]
    START_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    END_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    LABEL_FIELD_NUMBER: _ClassVar[int]
    DISPLAY_LABEL_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    event_id: str
    stream_id: str
    start_time_ms: int
    end_time_ms: int
    label: str
    display_label: str
    confidence: float
    model: ModelDescriptor
    def __init__(self, event_id: _Optional[str] = ..., stream_id: _Optional[str] = ..., start_time_ms: _Optional[int] = ..., end_time_ms: _Optional[int] = ..., label: _Optional[str] = ..., display_label: _Optional[str] = ..., confidence: _Optional[float] = ..., model: _Optional[_Union[ModelDescriptor, _Mapping]] = ...) -> None: ...

class DirectionEstimate(_message.Message):
    __slots__ = ("source_event_id", "direction", "angle_degrees", "confidence", "model")
    SOURCE_EVENT_ID_FIELD_NUMBER: _ClassVar[int]
    DIRECTION_FIELD_NUMBER: _ClassVar[int]
    ANGLE_DEGREES_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
    MODEL_FIELD_NUMBER: _ClassVar[int]
    source_event_id: str
    direction: Direction
    angle_degrees: float
    confidence: float
    model: ModelDescriptor
    def __init__(self, source_event_id: _Optional[str] = ..., direction: _Optional[_Union[Direction, str]] = ..., angle_degrees: _Optional[float] = ..., confidence: _Optional[float] = ..., model: _Optional[_Union[ModelDescriptor, _Mapping]] = ...) -> None: ...

class PerceptionEvent(_message.Message):
    __slots__ = ("event_id", "source_event_id", "kind", "title", "icon", "priority", "color", "direction", "start_time_ms", "end_time_ms", "lifetime_ms", "confidence")
    EVENT_ID_FIELD_NUMBER: _ClassVar[int]
    SOURCE_EVENT_ID_FIELD_NUMBER: _ClassVar[int]
    KIND_FIELD_NUMBER: _ClassVar[int]
    TITLE_FIELD_NUMBER: _ClassVar[int]
    ICON_FIELD_NUMBER: _ClassVar[int]
    PRIORITY_FIELD_NUMBER: _ClassVar[int]
    COLOR_FIELD_NUMBER: _ClassVar[int]
    DIRECTION_FIELD_NUMBER: _ClassVar[int]
    START_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    END_TIME_MS_FIELD_NUMBER: _ClassVar[int]
    LIFETIME_MS_FIELD_NUMBER: _ClassVar[int]
    CONFIDENCE_FIELD_NUMBER: _ClassVar[int]
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
    confidence: float
    def __init__(self, event_id: _Optional[str] = ..., source_event_id: _Optional[str] = ..., kind: _Optional[_Union[PerceptionKind, str]] = ..., title: _Optional[str] = ..., icon: _Optional[str] = ..., priority: _Optional[_Union[Priority, str]] = ..., color: _Optional[str] = ..., direction: _Optional[_Union[Direction, str]] = ..., start_time_ms: _Optional[int] = ..., end_time_ms: _Optional[int] = ..., lifetime_ms: _Optional[int] = ..., confidence: _Optional[float] = ...) -> None: ...

class StreamRequest(_message.Message):
    __slots__ = ("device_id", "sample_rate_hz", "channels", "frame_duration_ms", "queue_capacity")
    DEVICE_ID_FIELD_NUMBER: _ClassVar[int]
    SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    CHANNELS_FIELD_NUMBER: _ClassVar[int]
    FRAME_DURATION_MS_FIELD_NUMBER: _ClassVar[int]
    QUEUE_CAPACITY_FIELD_NUMBER: _ClassVar[int]
    device_id: str
    sample_rate_hz: int
    channels: int
    frame_duration_ms: int
    queue_capacity: int
    def __init__(self, device_id: _Optional[str] = ..., sample_rate_hz: _Optional[int] = ..., channels: _Optional[int] = ..., frame_duration_ms: _Optional[int] = ..., queue_capacity: _Optional[int] = ...) -> None: ...

class ListAudioDevicesRequest(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class AudioDevice(_message.Message):
    __slots__ = ("id", "name", "host_api", "max_input_channels", "default_sample_rate_hz", "is_default")
    ID_FIELD_NUMBER: _ClassVar[int]
    NAME_FIELD_NUMBER: _ClassVar[int]
    HOST_API_FIELD_NUMBER: _ClassVar[int]
    MAX_INPUT_CHANNELS_FIELD_NUMBER: _ClassVar[int]
    DEFAULT_SAMPLE_RATE_HZ_FIELD_NUMBER: _ClassVar[int]
    IS_DEFAULT_FIELD_NUMBER: _ClassVar[int]
    id: str
    name: str
    host_api: str
    max_input_channels: int
    default_sample_rate_hz: float
    is_default: bool
    def __init__(self, id: _Optional[str] = ..., name: _Optional[str] = ..., host_api: _Optional[str] = ..., max_input_channels: _Optional[int] = ..., default_sample_rate_hz: _Optional[float] = ..., is_default: _Optional[bool] = ...) -> None: ...

class AudioDeviceList(_message.Message):
    __slots__ = ("devices",)
    DEVICES_FIELD_NUMBER: _ClassVar[int]
    devices: _containers.RepeatedCompositeFieldContainer[AudioDevice]
    def __init__(self, devices: _Optional[_Iterable[_Union[AudioDevice, _Mapping]]] = ...) -> None: ...

class SpeechInput(_message.Message):
    __slots__ = ("frame", "activity")
    FRAME_FIELD_NUMBER: _ClassVar[int]
    ACTIVITY_FIELD_NUMBER: _ClassVar[int]
    frame: AudioFrame
    activity: VoiceActivity
    def __init__(self, frame: _Optional[_Union[AudioFrame, _Mapping]] = ..., activity: _Optional[_Union[VoiceActivity, _Mapping]] = ...) -> None: ...

class LocalizationInput(_message.Message):
    __slots__ = ("frame", "transcript", "sound")
    FRAME_FIELD_NUMBER: _ClassVar[int]
    TRANSCRIPT_FIELD_NUMBER: _ClassVar[int]
    SOUND_FIELD_NUMBER: _ClassVar[int]
    frame: AudioFrame
    transcript: TranscriptEvent
    sound: SoundEvent
    def __init__(self, frame: _Optional[_Union[AudioFrame, _Mapping]] = ..., transcript: _Optional[_Union[TranscriptEvent, _Mapping]] = ..., sound: _Optional[_Union[SoundEvent, _Mapping]] = ...) -> None: ...

class PerceptionInput(_message.Message):
    __slots__ = ("transcript", "sound", "direction")
    TRANSCRIPT_FIELD_NUMBER: _ClassVar[int]
    SOUND_FIELD_NUMBER: _ClassVar[int]
    DIRECTION_FIELD_NUMBER: _ClassVar[int]
    transcript: TranscriptEvent
    sound: SoundEvent
    direction: DirectionEstimate
    def __init__(self, transcript: _Optional[_Union[TranscriptEvent, _Mapping]] = ..., sound: _Optional[_Union[SoundEvent, _Mapping]] = ..., direction: _Optional[_Union[DirectionEstimate, _Mapping]] = ...) -> None: ...

class HealthRequest(_message.Message):
    __slots__ = ()
    def __init__(self) -> None: ...

class HealthResponse(_message.Message):
    __slots__ = ("service_name", "version", "ready", "capabilities")
    SERVICE_NAME_FIELD_NUMBER: _ClassVar[int]
    VERSION_FIELD_NUMBER: _ClassVar[int]
    READY_FIELD_NUMBER: _ClassVar[int]
    CAPABILITIES_FIELD_NUMBER: _ClassVar[int]
    service_name: str
    version: str
    ready: bool
    capabilities: _containers.RepeatedScalarFieldContainer[str]
    def __init__(self, service_name: _Optional[str] = ..., version: _Optional[str] = ..., ready: _Optional[bool] = ..., capabilities: _Optional[_Iterable[str]] = ...) -> None: ...
