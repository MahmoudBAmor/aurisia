from __future__ import annotations

import unittest
from pathlib import Path
from typing import Any

import numpy

from aurisia.contracts import ModelDescriptor
from aurisia.services.audio.adapters import SyntheticAudioSource
from aurisia.services.vad.adapters import SileroOnnxVadEngine


class _FakeSileroSession:
    def __init__(self) -> None:
        self.window_lengths: list[int] = []

    def run(
        self,
        output_names: object,
        inputs: dict[str, Any],
    ) -> list[numpy.ndarray[Any, Any]]:
        del output_names
        model_input = inputs["input"]
        self.window_lengths.append(int(model_input.shape[1]))
        probability = numpy.array([[0.8]], dtype=numpy.float32)
        return [probability, inputs["state"]]


class SileroVadTests(unittest.TestCase):
    def test_buffers_20ms_frames_into_non_overlapping_model_windows(self) -> None:
        session = _FakeSileroSession()
        engine = SileroOnnxVadEngine(
            Path("unused.onnx"),
            ModelDescriptor("silero-vad", "test", "onnxruntime"),
            session=session,
        )
        frames = tuple(SyntheticAudioSource([1_000, 1_000, 1_000, 1_000]).frames())

        probabilities = [engine.speech_probability(frame) for frame in frames]

        self.assertIsNone(probabilities[0])
        self.assertAlmostEqual(probabilities[1] or 0.0, 0.8)
        self.assertIsNone(probabilities[2])
        self.assertAlmostEqual(probabilities[3] or 0.0, 0.8)
        self.assertEqual(session.window_lengths, [576, 576])
        self.assertEqual(engine.metrics().inference_count, 2)

    def test_rejects_audio_that_bypasses_normalization(self) -> None:
        engine = SileroOnnxVadEngine(
            Path("unused.onnx"),
            ModelDescriptor("silero-vad", "test", "onnxruntime"),
            session=_FakeSileroSession(),
        )
        stereo_frame = next(
            iter(
                SyntheticAudioSource(
                    [1_000],
                    sample_rate_hz=48_000,
                ).frames()
            )
        )

        with self.assertRaisesRegex(ValueError, "16000 Hz mono"):
            engine.speech_probability(stereo_frame)


if __name__ == "__main__":
    unittest.main()
