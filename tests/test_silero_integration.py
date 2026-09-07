from __future__ import annotations

import unittest
from pathlib import Path

from aurisia.model_packs import ModelPackError, load_verified_model_pack
from aurisia.services.audio.adapters import SyntheticAudioSource
from aurisia.services.vad.adapters import SileroOnnxVadEngine


class SileroIntegrationTests(unittest.TestCase):
    def test_verified_cpu_model_rejects_synthetic_silence(self) -> None:
        manifest = Path("models/silero-vad-v6.2.1/manifest.yaml")
        try:
            pack = load_verified_model_pack(manifest)
        except ModelPackError as exc:
            self.skipTest(str(exc))
        engine = SileroOnnxVadEngine(
            pack.artifact("silero_vad").path,
            pack.model,
        )

        probabilities = [
            probability
            for frame in SyntheticAudioSource([0] * 100).frames()
            if (probability := engine.speech_probability(frame)) is not None
        ]

        self.assertTrue(probabilities)
        self.assertLess(max(probabilities), 0.1)
        self.assertGreater(engine.metrics().inference_count, 0)

    def test_verified_cpu_model_rejects_a_short_impulse(self) -> None:
        manifest = Path("models/silero-vad-v6.2.1/manifest.yaml")
        try:
            pack = load_verified_model_pack(manifest)
        except ModelPackError as exc:
            self.skipTest(str(exc))
        engine = SileroOnnxVadEngine(
            pack.artifact("silero_vad").path,
            pack.model,
        )

        probabilities = [
            probability
            for frame in SyntheticAudioSource([0] * 30 + [30_000] + [0] * 30).frames()
            if (probability := engine.speech_probability(frame)) is not None
        ]

        self.assertTrue(probabilities)
        self.assertLess(max(probabilities), 0.1)


if __name__ == "__main__":
    unittest.main()
