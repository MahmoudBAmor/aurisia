from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from typing import Any, cast

import numpy as np
import numpy.typing as npt

from aurisia.contracts import ModelDescriptor, SpeechSegment
from aurisia.services.speech import SpeechInferenceMeasurement
from aurisia.services.speech.adapters import MoonshineOnnxSpeechEngine


class _Result:
    text = "  كي تبدا ديسبو باللهي كلمني  "


class _Stream:
    result = _Result()

    def __init__(self) -> None:
        self.sample_rate = 0
        self.waveform = np.array([], dtype=np.float32)

    def accept_waveform(
        self,
        sample_rate: int,
        waveform: npt.NDArray[np.float32],
    ) -> None:
        self.sample_rate = sample_rate
        self.waveform = waveform


class _Recognizer:
    def __init__(self) -> None:
        self.stream = _Stream()
        self.decode_calls = 0
        self.asserts_same_stream = False

    def create_stream(self) -> _Stream:
        return self.stream

    def decode_stream(self, stream: _Stream) -> None:
        self.asserts_same_stream = stream is self.stream
        self.decode_calls += 1


class MoonshineOnnxSpeechEngineTests(unittest.TestCase):
    def test_transcribes_canonical_audio_and_records_latency(self) -> None:
        recognizer = _Recognizer()
        measurements: list[SpeechInferenceMeasurement] = []
        with tempfile.TemporaryDirectory() as directory:
            encoder, decoder, tokens = _artifacts(Path(directory))
            engine = MoonshineOnnxSpeechEngine(
                encoder_path=encoder,
                decoder_path=decoder,
                tokens_path=tokens,
                model=ModelDescriptor("moonshine-ar", "test", "sherpa-onnx"),
                supported_locale="aeb-TN",
                sample_rate_hz=16_000,
                channels=1,
                threads=2,
                recognizer_factory=cast(Any, lambda *args: recognizer),
                measurement_sink=measurements.append,
            )

            hypothesis = engine.transcribe(_segment(), "aeb-TN")

        self.assertEqual(hypothesis.text, "كي تبدا ديسبو باللهي كلمني")
        self.assertEqual(recognizer.decode_calls, 1)
        self.assertTrue(recognizer.asserts_same_stream)
        self.assertEqual(recognizer.stream.sample_rate, 16_000)
        self.assertEqual(recognizer.stream.waveform.dtype, np.float32)
        self.assertEqual(recognizer.stream.waveform.shape, (16_000,))
        self.assertAlmostEqual(float(recognizer.stream.waveform[0]), 0.5)
        self.assertEqual(measurements[0].audio_duration_ms, 1_000)

    def test_rejects_noncanonical_audio_before_inference(self) -> None:
        recognizer = _Recognizer()
        with tempfile.TemporaryDirectory() as directory:
            encoder, decoder, tokens = _artifacts(Path(directory))
            engine = MoonshineOnnxSpeechEngine(
                encoder_path=encoder,
                decoder_path=decoder,
                tokens_path=tokens,
                model=ModelDescriptor("moonshine-ar", "test", "sherpa-onnx"),
                supported_locale="aeb-TN",
                sample_rate_hz=16_000,
                channels=1,
                threads=2,
                recognizer_factory=cast(Any, lambda *args: recognizer),
            )
            segment = SpeechSegment(
                segment_id="speech:0-1",
                stream_id="speech",
                start_time_ms=0,
                end_time_ms=20,
                sample_rate_hz=48_000,
                channels=1,
                pcm_s16le=b"\x00\x00" * 960,
            )

            with self.assertRaisesRegex(ValueError, "audio contract"):
                engine.transcribe(segment, "aeb-TN")

        self.assertEqual(recognizer.decode_calls, 0)


def _artifacts(root: Path) -> tuple[Path, Path, Path]:
    paths = (
        root / "encoder.ort",
        root / "decoder.ort",
        root / "tokens.txt",
    )
    for path in paths:
        path.write_bytes(b"test")
    return paths


def _segment() -> SpeechSegment:
    sample = (16_384).to_bytes(2, byteorder="little", signed=True)
    return SpeechSegment(
        segment_id="speech:0-49",
        stream_id="speech",
        start_time_ms=0,
        end_time_ms=1_000,
        sample_rate_hz=16_000,
        channels=1,
        pcm_s16le=sample * 16_000,
    )


if __name__ == "__main__":
    unittest.main()
