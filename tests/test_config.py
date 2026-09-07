from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from aurisia.config import ConfigError, load_config


class ConfigTests(unittest.TestCase):
    def test_reference_configuration_is_strict_and_offline(self) -> None:
        config = load_config(Path("config/aurisia.yaml"))

        self.assertTrue(config.runtime.offline)
        self.assertFalse(config.platform.gpu_required)
        self.assertEqual(config.platform.os, "windows_11")
        self.assertEqual(config.platform.architecture, "x86_64")
        self.assertEqual(config.audio.sample_rate_hz, 16_000)
        self.assertEqual(config.audio.channels, 1)
        self.assertEqual(config.audio.grpc_endpoint, "127.0.0.1:50051")
        self.assertEqual(config.normalization.sample_rate_hz, 16_000)
        self.assertEqual(config.normalization.channels, 1)
        self.assertEqual(config.vad.energy_reference_rms, 450.0)
        self.assertEqual(config.vad.start_probability, 0.5)
        self.assertEqual(config.vad.end_probability, 0.35)
        self.assertEqual(config.vad.end_silence_frames, 9)
        self.assertTrue(config.vad.model_manifest_path.is_file())
        self.assertEqual(config.models.vad_adapter, "silero_onnx")
        self.assertEqual(config.models.speech_adapter, "linto_vosk")
        self.assertEqual(config.speech.language, "ar")
        self.assertEqual(config.speech.threads, 4)
        self.assertEqual(config.speech.endpoint, "127.0.0.1:50052")
        self.assertEqual(config.speech.minimum_segment_ms, 300)
        self.assertEqual(config.speech.pre_roll_ms, 300)
        self.assertEqual(config.speech.partial_interval_ms, 750)
        self.assertEqual(config.speech.maximum_segment_ms, 30_000)
        self.assertTrue(config.speech.model_manifest_path.is_file())
        self.assertEqual(config.language.locale, "aeb-TN")
        self.assertEqual(config.language.display_mode, "arabic")
        self.assertEqual(config.language.direction, "rtl")
        self.assertTrue(config.language.lexicon_path.is_file())

    def test_unknown_configuration_key_is_rejected(self) -> None:
        original = Path("config/aurisia.yaml").read_text(encoding="utf-8")
        invalid = original.replace("  offline: true", "  offline: true\n  telemetry: true")
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "invalid.yaml"
            path.write_text(invalid, encoding="utf-8")
            with self.assertRaisesRegex(ConfigError, "unknown keys: telemetry"):
                load_config(path)


if __name__ == "__main__":
    unittest.main()
