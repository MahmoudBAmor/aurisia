"""Deterministic composition used by local development and the desktop HUD."""

from __future__ import annotations

from aurisia.config import AppConfig
from aurisia.language import ArabicScriptNormalizer
from aurisia.services.audio import AudioCaptureService
from aurisia.services.audio.adapters import SyntheticAudioSource
from aurisia.services.localization import LocalizationService
from aurisia.services.localization.adapters import DeterministicDirectionEngine
from aurisia.services.perception import PerceptionService
from aurisia.services.sound_detection import SoundDetectionService
from aurisia.services.sound_detection.adapters import ScriptedSoundEngine
from aurisia.services.sound_detection.ports import SoundHypothesis
from aurisia.services.speech import SpeechRecognitionService
from aurisia.services.speech.adapters import ScriptedSpeechEngine
from aurisia.services.vad import VadService
from aurisia.services.vad.adapters import EnergyVadEngine

from .pipeline import PerceptionPipeline


def build_demo_pipeline(config: AppConfig) -> PerceptionPipeline:
    """Build the first offline vertical slice from replaceable adapters."""

    _validate_demo_adapters(config)
    normalizer = ArabicScriptNormalizer.from_yaml(config.language.lexicon_path)
    sound_labels = {
        "sound.alert.doorbell": "جرس الباب",
    }
    return PerceptionPipeline(
        audio=AudioCaptureService(SyntheticAudioSource.demo_scenario()),
        vad=VadService(EnergyVadEngine()),
        speech=SpeechRecognitionService(
            ScriptedSpeechEngine(["نحب نعمل rendez-vous غدوة على 10"]),
            normalizer,
            locale=config.language.locale,
        ),
        sound=SoundDetectionService(
            ScriptedSoundEngine(
                {
                    65: (
                        SoundHypothesis(
                            canonical_label="sound.alert.doorbell",
                            confidence=0.88,
                            duration_ms=960,
                        ),
                    )
                }
            ),
            sound_labels,
        ),
        localization=LocalizationService(DeterministicDirectionEngine()),
        perception=PerceptionService(event_lifetime_ms=config.hud.event_lifetime_ms),
    )


def _validate_demo_adapters(config: AppConfig) -> None:
    selected = {
        config.models.vad_adapter,
        config.models.speech_adapter,
        config.models.sound_adapter,
        config.models.localization_adapter,
    }
    supported = {
        "energy_vad",
        "silero_onnx",
        "scripted_aeb_tn",
        "linto_vosk",
        "moonshine_onnx",
        "whisper_cpp",
        "scripted_sound",
        "deterministic_direction",
    }
    required = {
        "scripted_sound",
        "deterministic_direction",
    }
    unknown = selected - supported
    if unknown or not required.issubset(selected):
        raise ValueError(f"unsupported demo adapters: {', '.join(sorted(unknown))}")
