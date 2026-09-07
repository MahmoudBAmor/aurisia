"""Validated Aurisia configuration."""

from .loader import (
    AppConfig,
    AudioConfig,
    AudioNormalizationConfig,
    ConfigError,
    HudConfig,
    LanguageConfig,
    ModelConfig,
    PlatformConfig,
    RuntimeConfig,
    SpeechConfig,
    VadConfig,
    load_config,
)

__all__ = [
    "AppConfig",
    "AudioConfig",
    "AudioNormalizationConfig",
    "ConfigError",
    "HudConfig",
    "LanguageConfig",
    "ModelConfig",
    "PlatformConfig",
    "RuntimeConfig",
    "SpeechConfig",
    "VadConfig",
    "load_config",
]
