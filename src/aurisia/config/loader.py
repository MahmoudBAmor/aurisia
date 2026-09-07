"""Strict YAML configuration loader.

Configuration is deliberately parsed into immutable standard-library
dataclasses. Model SDKs never leak into configuration or service contracts.
"""

from __future__ import annotations

from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


class ConfigError(ValueError):
    """Raised when the application configuration is invalid."""


@dataclass(frozen=True, slots=True)
class RuntimeConfig:
    offline: bool
    transport: str
    audio_queue_capacity: int


@dataclass(frozen=True, slots=True)
class AudioConfig:
    device: str
    sample_rate_hz: int
    channels: int
    frame_duration_ms: int
    ring_buffer_seconds: int
    reconnect_delay_ms: int
    grpc_endpoint: str


@dataclass(frozen=True, slots=True)
class AudioNormalizationConfig:
    sample_rate_hz: int
    channels: int
    frame_duration_ms: int
    quality: str


@dataclass(frozen=True, slots=True)
class VadConfig:
    energy_reference_rms: float
    start_probability: float
    end_probability: float
    end_silence_frames: int
    model_manifest_path: Path


@dataclass(frozen=True, slots=True)
class SpeechConfig:
    model_manifest_path: Path
    executable_path: Path
    executable_sha256: str
    endpoint: str
    language: str
    threads: int
    startup_timeout_seconds: float
    timeout_seconds: float
    minimum_segment_ms: int
    pre_roll_ms: int
    partial_interval_ms: int
    maximum_segment_ms: int


@dataclass(frozen=True, slots=True)
class PlatformConfig:
    os: str
    architecture: str
    gpu_required: bool
    reference_ram_gb: int


@dataclass(frozen=True, slots=True)
class LanguageConfig:
    locale: str
    display_mode: str
    direction: str
    digits: str
    lexicon_path: Path


@dataclass(frozen=True, slots=True)
class ModelConfig:
    vad_adapter: str
    speech_adapter: str
    sound_adapter: str
    localization_adapter: str


@dataclass(frozen=True, slots=True)
class HudConfig:
    fps: int
    click_through: bool
    event_lifetime_ms: int


@dataclass(frozen=True, slots=True)
class AppConfig:
    schema_version: int
    runtime: RuntimeConfig
    audio: AudioConfig
    normalization: AudioNormalizationConfig
    vad: VadConfig
    speech: SpeechConfig
    platform: PlatformConfig
    language: LanguageConfig
    models: ModelConfig
    hud: HudConfig


def load_config(path: Path) -> AppConfig:
    """Load and strictly validate an Aurisia YAML configuration file."""

    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ConfigError(f"cannot read configuration {path}: {exc}") from exc
    except yaml.YAMLError as exc:
        raise ConfigError(f"invalid YAML in {path}: {exc}") from exc

    root = _mapping(raw, "root")
    _keys(
        root,
        {
            "schema_version",
            "runtime",
            "audio",
            "normalization",
            "vad",
            "speech",
            "platform",
            "language",
            "models",
            "hud",
        },
        "root",
    )
    schema_version = _integer(root, "schema_version", "root")
    if schema_version != 1:
        raise ConfigError(f"unsupported schema_version {schema_version}; expected 1")

    runtime_raw = _section(root, "runtime", {"offline", "transport", "audio_queue_capacity"})
    runtime = RuntimeConfig(
        offline=_boolean(runtime_raw, "offline", "runtime"),
        transport=_choice(runtime_raw, "transport", {"in_process", "local_grpc"}, "runtime"),
        audio_queue_capacity=_positive_int(runtime_raw, "audio_queue_capacity", "runtime"),
    )
    if not runtime.offline:
        raise ConfigError("the MVP must run with runtime.offline=true")

    audio_raw = _section(
        root,
        "audio",
        {
            "device",
            "sample_rate_hz",
            "channels",
            "frame_duration_ms",
            "ring_buffer_seconds",
            "reconnect_delay_ms",
            "grpc_endpoint",
        },
    )
    grpc_endpoint = _string(audio_raw, "grpc_endpoint", "audio")
    _validate_loopback_endpoint(grpc_endpoint, path="audio.grpc_endpoint")
    audio = AudioConfig(
        device=_string(audio_raw, "device", "audio"),
        sample_rate_hz=_bounded_int(audio_raw, "sample_rate_hz", 8_000, 192_000, "audio"),
        channels=_bounded_int(audio_raw, "channels", 1, 8, "audio"),
        frame_duration_ms=_bounded_int(audio_raw, "frame_duration_ms", 10, 100, "audio"),
        ring_buffer_seconds=_bounded_int(audio_raw, "ring_buffer_seconds", 1, 120, "audio"),
        reconnect_delay_ms=_bounded_int(audio_raw, "reconnect_delay_ms", 100, 30_000, "audio"),
        grpc_endpoint=grpc_endpoint,
    )

    normalization_raw = _section(
        root,
        "normalization",
        {"sample_rate_hz", "channels", "frame_duration_ms", "quality"},
    )
    normalization = AudioNormalizationConfig(
        sample_rate_hz=_bounded_int(
            normalization_raw,
            "sample_rate_hz",
            8_000,
            192_000,
            "normalization",
        ),
        channels=_bounded_int(normalization_raw, "channels", 1, 8, "normalization"),
        frame_duration_ms=_bounded_int(
            normalization_raw,
            "frame_duration_ms",
            10,
            100,
            "normalization",
        ),
        quality=_choice(
            normalization_raw,
            "quality",
            {"QQ", "LQ", "MQ", "HQ", "VHQ"},
            "normalization",
        ),
    )
    if normalization.channels != 1:
        raise ConfigError("the current canonical model stream must be mono")

    vad_raw = _section(
        root,
        "vad",
        {
            "energy_reference_rms",
            "start_probability",
            "end_probability",
            "end_silence_frames",
            "model_manifest_path",
        },
    )
    start_probability = _bounded_number(
        vad_raw,
        "start_probability",
        0.0,
        1.0,
        "vad",
    )
    end_probability = _bounded_number(
        vad_raw,
        "end_probability",
        0.0,
        1.0,
        "vad",
    )
    if end_probability > start_probability:
        raise ConfigError("vad.end_probability must not exceed vad.start_probability")
    vad = VadConfig(
        energy_reference_rms=_positive_number(
            vad_raw,
            "energy_reference_rms",
            "vad",
        ),
        start_probability=start_probability,
        end_probability=end_probability,
        end_silence_frames=_positive_int(vad_raw, "end_silence_frames", "vad"),
        model_manifest_path=(
            path.parent / _string(vad_raw, "model_manifest_path", "vad")
        ).resolve(),
    )

    speech_raw = _section(
        root,
        "speech",
        {
            "model_manifest_path",
            "executable_path",
            "executable_sha256",
            "endpoint",
            "language",
            "threads",
            "startup_timeout_seconds",
            "timeout_seconds",
            "minimum_segment_ms",
            "pre_roll_ms",
            "partial_interval_ms",
            "maximum_segment_ms",
        },
    )
    executable_sha256 = _string(speech_raw, "executable_sha256", "speech").lower()
    if len(executable_sha256) != 64 or any(
        character not in "0123456789abcdef" for character in executable_sha256
    ):
        raise ConfigError("speech.executable_sha256 must be a lowercase SHA-256 digest")
    speech_language = _string(speech_raw, "language", "speech")
    if speech_language != "ar":
        raise ConfigError("Tunisian Arabic speech recognition requires speech.language=ar")
    speech_endpoint = _string(speech_raw, "endpoint", "speech")
    _validate_loopback_endpoint(speech_endpoint, path="speech.endpoint")
    speech = SpeechConfig(
        model_manifest_path=(
            path.parent / _string(speech_raw, "model_manifest_path", "speech")
        ).resolve(),
        executable_path=(
            path.parent / _string(speech_raw, "executable_path", "speech")
        ).resolve(),
        executable_sha256=executable_sha256,
        endpoint=speech_endpoint,
        language=speech_language,
        threads=_bounded_int(speech_raw, "threads", 1, 32, "speech"),
        startup_timeout_seconds=_positive_number(
            speech_raw,
            "startup_timeout_seconds",
            "speech",
        ),
        timeout_seconds=_positive_number(speech_raw, "timeout_seconds", "speech"),
        minimum_segment_ms=_bounded_int(
            speech_raw,
            "minimum_segment_ms",
            100,
            5_000,
            "speech",
        ),
        pre_roll_ms=_bounded_int(speech_raw, "pre_roll_ms", 0, 2_000, "speech"),
        partial_interval_ms=_bounded_int(
            speech_raw,
            "partial_interval_ms",
            100,
            5_000,
            "speech",
        ),
        maximum_segment_ms=_bounded_int(
            speech_raw,
            "maximum_segment_ms",
            1_000,
            120_000,
            "speech",
        ),
    )
    if speech.maximum_segment_ms < speech.minimum_segment_ms:
        raise ConfigError(
            "speech.maximum_segment_ms must not be shorter than "
            "speech.minimum_segment_ms"
        )

    platform_raw = _section(
        root,
        "platform",
        {"os", "architecture", "gpu_required", "reference_ram_gb"},
    )
    platform = PlatformConfig(
        os=_string(platform_raw, "os", "platform"),
        architecture=_string(platform_raw, "architecture", "platform"),
        gpu_required=_boolean(platform_raw, "gpu_required", "platform"),
        reference_ram_gb=_positive_int(platform_raw, "reference_ram_gb", "platform"),
    )

    language_raw = _section(
        root,
        "language",
        {"locale", "display_mode", "direction", "digits", "lexicon_path"},
    )
    locale = _string(language_raw, "locale", "language")
    if locale != "aeb-TN":
        raise ConfigError("the first language pack must use locale aeb-TN")
    display_mode = _choice(
        language_raw,
        "display_mode",
        {"arabic", "arabizi", "auto_mixed"},
        "language",
    )
    direction = _choice(language_raw, "direction", {"rtl", "ltr"}, "language")
    if display_mode == "arabic" and direction != "rtl":
        raise ConfigError("Arabic display mode requires language.direction=rtl")
    lexicon_value = _string(language_raw, "lexicon_path", "language")
    lexicon_path = (path.parent / lexicon_value).resolve()
    language = LanguageConfig(
        locale=locale,
        display_mode=display_mode,
        direction=direction,
        digits=_choice(language_raw, "digits", {"european", "arabic_indic"}, "language"),
        lexicon_path=lexicon_path,
    )

    models_raw = _section(
        root,
        "models",
        {"vad_adapter", "speech_adapter", "sound_adapter", "localization_adapter"},
    )
    models = ModelConfig(
        vad_adapter=_string(models_raw, "vad_adapter", "models"),
        speech_adapter=_string(models_raw, "speech_adapter", "models"),
        sound_adapter=_string(models_raw, "sound_adapter", "models"),
        localization_adapter=_string(models_raw, "localization_adapter", "models"),
    )

    hud_raw = _section(root, "hud", {"fps", "click_through", "event_lifetime_ms"})
    hud = HudConfig(
        fps=_bounded_int(hud_raw, "fps", 1, 120, "hud"),
        click_through=_boolean(hud_raw, "click_through", "hud"),
        event_lifetime_ms=_positive_int(hud_raw, "event_lifetime_ms", "hud"),
    )

    return AppConfig(
        schema_version=schema_version,
        runtime=runtime,
        audio=audio,
        normalization=normalization,
        vad=vad,
        speech=speech,
        platform=platform,
        language=language,
        models=models,
        hud=hud,
    )


def _section(root: Mapping[str, Any], name: str, expected: set[str]) -> Mapping[str, Any]:
    section = _mapping(root.get(name), name)
    _keys(section, expected, name)
    return section


def _mapping(value: Any, path: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ConfigError(f"{path} must be a mapping")
    return value


def _keys(value: Mapping[str, Any], expected: set[str], path: str) -> None:
    missing = expected - value.keys()
    unknown = value.keys() - expected
    if missing:
        raise ConfigError(f"{path} is missing keys: {', '.join(sorted(missing))}")
    if unknown:
        raise ConfigError(f"{path} contains unknown keys: {', '.join(sorted(unknown))}")


def _string(value: Mapping[str, Any], key: str, path: str) -> str:
    item = value.get(key)
    if not isinstance(item, str) or not item.strip():
        raise ConfigError(f"{path}.{key} must be a non-empty string")
    return item.strip()


def _boolean(value: Mapping[str, Any], key: str, path: str) -> bool:
    item = value.get(key)
    if type(item) is not bool:
        raise ConfigError(f"{path}.{key} must be a boolean")
    return item


def _integer(value: Mapping[str, Any], key: str, path: str) -> int:
    item = value.get(key)
    if type(item) is not int:
        raise ConfigError(f"{path}.{key} must be an integer")
    return item


def _positive_int(value: Mapping[str, Any], key: str, path: str) -> int:
    item = _integer(value, key, path)
    if item <= 0:
        raise ConfigError(f"{path}.{key} must be positive")
    return item


def _number(value: Mapping[str, Any], key: str, path: str) -> float:
    item = value.get(key)
    if isinstance(item, bool) or not isinstance(item, (int, float)):
        raise ConfigError(f"{path}.{key} must be a number")
    return float(item)


def _positive_number(value: Mapping[str, Any], key: str, path: str) -> float:
    item = _number(value, key, path)
    if item <= 0:
        raise ConfigError(f"{path}.{key} must be positive")
    return item


def _bounded_number(
    value: Mapping[str, Any],
    key: str,
    minimum: float,
    maximum: float,
    path: str,
) -> float:
    item = _number(value, key, path)
    if not minimum <= item <= maximum:
        raise ConfigError(f"{path}.{key} must be between {minimum} and {maximum}")
    return item


def _bounded_int(
    value: Mapping[str, Any],
    key: str,
    minimum: int,
    maximum: int,
    path: str,
) -> int:
    item = _integer(value, key, path)
    if not minimum <= item <= maximum:
        raise ConfigError(f"{path}.{key} must be between {minimum} and {maximum}")
    return item


def _choice(
    value: Mapping[str, Any],
    key: str,
    choices: set[str],
    path: str,
) -> str:
    item = _string(value, key, path)
    if item not in choices:
        raise ConfigError(f"{path}.{key} must be one of: {', '.join(sorted(choices))}")
    return item


def _validate_loopback_endpoint(endpoint: str, *, path: str) -> None:
    try:
        host, port_text = endpoint.rsplit(":", maxsplit=1)
        port = int(port_text)
    except ValueError as exc:
        raise ConfigError(f"{path} must use host:port syntax") from exc
    if host not in {"127.0.0.1", "localhost", "[::1]"}:
        raise ConfigError(f"{path} must bind to loopback")
    if not 1 <= port <= 65_535:
        raise ConfigError(f"{path} port must be in [1, 65535]")
