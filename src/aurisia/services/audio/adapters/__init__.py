"""Audio source adapters."""

from .normalized import AudioNormalizationUnavailable, NormalizingAudioSource
from .sounddevice_source import (
    AudioBackendUnavailable,
    AudioDeviceSelectionError,
    SoundDeviceAudioSource,
    list_input_devices,
    resolve_device_selector,
)
from .synthetic import SyntheticAudioSource
from .wave_file import WaveFileAudioSource

__all__ = [
    "AudioBackendUnavailable",
    "AudioDeviceSelectionError",
    "AudioNormalizationUnavailable",
    "AudioServiceUnavailable",
    "GrpcAudioSource",
    "NormalizingAudioSource",
    "SoundDeviceAudioSource",
    "SyntheticAudioSource",
    "WaveFileAudioSource",
    "list_input_devices",
    "list_remote_input_devices",
    "resolve_device_selector",
    "wait_for_audio_service",
]
from .grpc_source import (
    AudioServiceUnavailable,
    GrpcAudioSource,
    list_remote_input_devices,
    wait_for_audio_service,
)
