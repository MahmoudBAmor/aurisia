"""Speech engine adapters."""

from .moonshine_onnx import MoonshineOnnxSpeechEngine, MoonshineRuntimeUnavailable
from .scripted import ScriptedSpeechEngine
from .vosk import VoskRuntimeUnavailable, VoskSpeechEngine
from .whisper_cpp import (
    WhisperCppSpeechEngine,
    WhisperServiceUnavailable,
    verify_whisper_runtime,
    wait_for_whisper_service,
)

__all__ = [
    "MoonshineOnnxSpeechEngine",
    "MoonshineRuntimeUnavailable",
    "ScriptedSpeechEngine",
    "VoskRuntimeUnavailable",
    "VoskSpeechEngine",
    "WhisperCppSpeechEngine",
    "WhisperServiceUnavailable",
    "verify_whisper_runtime",
    "wait_for_whisper_service",
]
