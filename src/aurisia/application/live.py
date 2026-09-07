"""Composition for the real microphone path with replaceable model adapters."""

from __future__ import annotations

from collections.abc import Callable

from aurisia.config import AppConfig
from aurisia.language import ArabicScriptNormalizer
from aurisia.model_packs import load_verified_model_pack
from aurisia.services.audio import AudioCaptureService
from aurisia.services.audio.adapters import NormalizingAudioSource
from aurisia.services.audio.buffer import CircularAudioBuffer
from aurisia.services.audio.ports import AudioSource
from aurisia.services.localization import LocalizationService
from aurisia.services.localization.adapters import DeterministicDirectionEngine
from aurisia.services.perception import PerceptionService
from aurisia.services.sound_detection import SoundDetectionService
from aurisia.services.sound_detection.adapters import SilentSoundEngine
from aurisia.services.speech import SpeechInferenceMeasurement, SpeechRecognitionService
from aurisia.services.speech.adapters import (
    MoonshineOnnxSpeechEngine,
    ScriptedSpeechEngine,
    VoskSpeechEngine,
    WhisperCppSpeechEngine,
)
from aurisia.services.speech.ports import SpeechEngine
from aurisia.services.vad import VadService
from aurisia.services.vad.adapters import EnergyVadEngine, SileroOnnxVadEngine
from aurisia.services.vad.ports import VadEngine

from .pipeline import PerceptionPipeline


def build_live_pipeline(
    config: AppConfig,
    audio_source: AudioSource,
    *,
    speech_measurement_sink: Callable[[SpeechInferenceMeasurement], None] | None = None,
) -> PerceptionPipeline:
    """Compose live transport with configured production and fallback adapters."""

    normalizer = ArabicScriptNormalizer.from_yaml(config.language.lexicon_path)
    normalized_audio = build_normalized_audio_source(config, audio_source)
    buffer_capacity = (
        config.audio.ring_buffer_seconds * 1000 // config.normalization.frame_duration_ms
    )
    return PerceptionPipeline(
        audio=AudioCaptureService(
            normalized_audio,
            ring_buffer=CircularAudioBuffer(buffer_capacity),
        ),
        vad=VadService(
            build_live_vad_engine(config),
            start_threshold=config.vad.start_probability,
            end_threshold=config.vad.end_probability,
            end_silence_frames=config.vad.end_silence_frames,
        ),
        speech=SpeechRecognitionService(
            build_live_speech_engine(
                config,
                measurement_sink=speech_measurement_sink,
            ),
            normalizer,
            locale=config.language.locale,
            minimum_segment_ms=config.speech.minimum_segment_ms,
        ),
        sound=SoundDetectionService(SilentSoundEngine(), {}),
        localization=LocalizationService(DeterministicDirectionEngine()),
        perception=PerceptionService(event_lifetime_ms=config.hud.event_lifetime_ms),
        speech_pre_roll_ms=config.speech.pre_roll_ms,
        speech_partial_interval_ms=config.speech.partial_interval_ms,
        speech_maximum_segment_ms=config.speech.maximum_segment_ms,
    )


def build_live_speech_engine(
    config: AppConfig,
    *,
    measurement_sink: Callable[[SpeechInferenceMeasurement], None] | None = None,
) -> SpeechEngine:
    """Build the selected ASR adapter behind the service-owned speech port."""

    if config.models.speech_adapter == "scripted_aeb_tn":
        return ScriptedSpeechEngine(
            ["نحب نعمل rendez-vous غدوة على 10"],
            repeat=True,
        )
    if config.models.speech_adapter not in {
        "linto_vosk",
        "moonshine_onnx",
        "whisper_cpp",
    }:
        raise ValueError(
            f"unsupported live speech adapter: {config.models.speech_adapter}"
        )

    pack = load_verified_model_pack(config.speech.model_manifest_path)
    expected_input = (
        config.normalization.sample_rate_hz,
        config.normalization.channels,
        "pcm_s16le",
    )
    actual_input = (
        pack.input.sample_rate_hz,
        pack.input.channels,
        pack.input.sample_format,
    )
    if actual_input != expected_input:
        raise ValueError(
            "speech model input does not match canonical audio normalization: "
            f"model={actual_input}, normalization={expected_input}"
        )
    if config.models.speech_adapter == "moonshine_onnx":
        return MoonshineOnnxSpeechEngine(
            encoder_path=pack.artifact("moonshine_encoder").path,
            decoder_path=pack.artifact("moonshine_decoder").path,
            tokens_path=pack.artifact("tokens").path,
            model=pack.model,
            supported_locale=config.language.locale,
            sample_rate_hz=pack.input.sample_rate_hz,
            channels=pack.input.channels,
            threads=config.speech.threads,
            measurement_sink=measurement_sink,
        )
    if config.models.speech_adapter == "linto_vosk":
        artifact = pack.artifact("vosk_model")
        if artifact.kind != "directory":
            raise ValueError("the Vosk adapter requires a directory model artifact")
        return VoskSpeechEngine(
            model_directory=artifact.path,
            model=pack.model,
            supported_locale=config.language.locale,
            sample_rate_hz=pack.input.sample_rate_hz,
            channels=pack.input.channels,
            measurement_sink=measurement_sink,
        )
    return WhisperCppSpeechEngine(
        endpoint=config.speech.endpoint,
        model=pack.model,
        language=config.speech.language,
        supported_locale=config.language.locale,
        sample_rate_hz=pack.input.sample_rate_hz,
        channels=pack.input.channels,
        timeout_seconds=config.speech.timeout_seconds,
        measurement_sink=measurement_sink,
    )


def build_normalized_audio_source(
    config: AppConfig,
    audio_source: AudioSource,
) -> NormalizingAudioSource:
    """Adapt a platform source to Aurisia's canonical model audio contract."""

    return NormalizingAudioSource(
        audio_source,
        sample_rate_hz=config.normalization.sample_rate_hz,
        frame_duration_ms=config.normalization.frame_duration_ms,
        quality=config.normalization.quality,
    )


def build_live_vad_engine(config: AppConfig) -> VadEngine:
    """Build the selected VAD adapter without leaking its runtime downstream."""

    if config.models.vad_adapter == "energy_vad":
        return EnergyVadEngine(rms_threshold=config.vad.energy_reference_rms)
    if config.models.vad_adapter != "silero_onnx":
        raise ValueError(f"unsupported live VAD adapter: {config.models.vad_adapter}")

    pack = load_verified_model_pack(config.vad.model_manifest_path)
    expected_input = (
        config.normalization.sample_rate_hz,
        config.normalization.channels,
    )
    actual_input = (pack.input.sample_rate_hz, pack.input.channels)
    if actual_input != expected_input:
        raise ValueError(
            "VAD model input does not match canonical audio normalization: "
            f"model={actual_input}, normalization={expected_input}"
        )
    if pack.input.window_samples != 512:
        raise ValueError("the Silero adapter requires a 512-sample model window")
    artifact = pack.artifact("silero_vad")
    return SileroOnnxVadEngine(artifact.path, pack.model)
