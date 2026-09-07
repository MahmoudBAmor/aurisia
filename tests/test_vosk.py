from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path
from typing import Any, cast

from aurisia.contracts import ModelDescriptor, SpeechSegment
from aurisia.services.speech import SpeechInferenceMeasurement
from aurisia.services.speech.adapters import VoskRuntimeUnavailable, VoskSpeechEngine


class _Recognizer:
    def __init__(self, result: dict[str, Any]) -> None:
        self._result = result
        self.words_enabled = False
        self.received_pcm = b""
        self.accepted_chunks: list[bytes] = []

    def SetWords(self, enabled: bool) -> None:
        self.words_enabled = enabled

    def AcceptWaveform(self, pcm_s16le: bytes) -> bool:
        self.received_pcm += pcm_s16le
        self.accepted_chunks.append(pcm_s16le)
        return False

    def Result(self) -> str:
        return json.dumps({"text": ""})

    def PartialResult(self) -> str:
        return json.dumps({"partial": self._result.get("text", "")})

    def FinalResult(self) -> str:
        return json.dumps(self._result)


class VoskSpeechEngineTests(unittest.TestCase):
    def test_transcribes_with_persistent_model_and_averages_word_confidence(self) -> None:
        recognizer = _Recognizer(
            {
                "text": "امشي لل pharmacie وإيجا",
                "result": [{"conf": 0.8}, {"conf": 0.6}, {"conf": 1.2}],
            }
        )
        model_handle = object()
        loaded_paths: list[Path] = []
        measurements: list[SpeechInferenceMeasurement] = []

        def model_factory(path: Path) -> object:
            loaded_paths.append(path)
            return model_handle

        with tempfile.TemporaryDirectory() as directory:
            model_directory = Path(directory)
            engine = VoskSpeechEngine(
                model_directory=model_directory,
                model=ModelDescriptor("linto", "test", "vosk"),
                supported_locale="aeb-TN",
                sample_rate_hz=16_000,
                channels=1,
                model_factory=model_factory,
                recognizer_factory=cast(Any, lambda model, rate: recognizer),
                measurement_sink=measurements.append,
            )

            hypothesis = engine.transcribe(_segment(), "aeb-TN")

        self.assertEqual(loaded_paths, [model_directory])
        self.assertEqual(hypothesis.text, "امشي لل pharmacie وإيجا")
        self.assertAlmostEqual(hypothesis.confidence or 0.0, 0.8)
        self.assertTrue(recognizer.words_enabled)
        self.assertEqual(recognizer.received_pcm, _segment().pcm_s16le)
        self.assertEqual(measurements[0].audio_duration_ms, 1_000)
        self.assertIsNotNone(measurements[0].finalization_latency_ms)

    def test_streaming_session_decodes_each_chunk_before_finalization(self) -> None:
        recognizer = _Recognizer({"text": "نص", "result": [{"conf": 0.9}]})
        measurements: list[SpeechInferenceMeasurement] = []

        with tempfile.TemporaryDirectory() as directory:
            engine = VoskSpeechEngine(
                model_directory=Path(directory),
                model=ModelDescriptor("linto", "test", "vosk"),
                supported_locale="aeb-TN",
                sample_rate_hz=16_000,
                channels=1,
                model_factory=lambda path: object(),
                recognizer_factory=cast(Any, lambda model, rate: recognizer),
                measurement_sink=measurements.append,
            )
            session = engine.start_stream("aeb-TN", 16_000, 1)

            session.accept_pcm(b"\x01\x00" * 320)
            session.accept_pcm(b"\x02\x00" * 320)
            hypothesis = session.finish(40)

        self.assertEqual(recognizer.accepted_chunks, [b"\x01\x00" * 320, b"\x02\x00" * 320])
        self.assertEqual(hypothesis.text, "نص")
        self.assertEqual(len(measurements), 1)
        self.assertGreaterEqual(measurements[0].finalization_latency_ms or 0.0, 0.0)
        with self.assertRaisesRegex(RuntimeError, "already finished"):
            session.accept_pcm(b"\x00\x00")

    def test_streaming_session_preserves_decoder_internal_endpoints(self) -> None:
        class EndpointRecognizer(_Recognizer):
            def AcceptWaveform(self, pcm_s16le: bytes) -> bool:
                super().AcceptWaveform(pcm_s16le)
                return len(self.accepted_chunks) == 1

            def Result(self) -> str:
                return json.dumps({"text": "الجزء الأول"})

            def FinalResult(self) -> str:
                return json.dumps({"text": "الجزء الثاني"})

        recognizer = EndpointRecognizer({})
        with tempfile.TemporaryDirectory() as directory:
            engine = VoskSpeechEngine(
                model_directory=Path(directory),
                model=ModelDescriptor("linto", "test", "vosk"),
                supported_locale="aeb-TN",
                sample_rate_hz=16_000,
                channels=1,
                model_factory=lambda path: object(),
                recognizer_factory=cast(Any, lambda model, rate: recognizer),
            )
            session = engine.start_stream("aeb-TN", 16_000, 1)

            session.accept_pcm(b"\x01\x00" * 320)
            session.accept_pcm(b"\x02\x00" * 320)
            hypothesis = session.finish(40)

        self.assertEqual(hypothesis.text, "الجزء الأول الجزء الثاني")

    def test_streaming_session_exposes_completed_and_partial_text(self) -> None:
        class PartialRecognizer(_Recognizer):
            def AcceptWaveform(self, pcm_s16le: bytes) -> bool:
                super().AcceptWaveform(pcm_s16le)
                return len(self.accepted_chunks) == 1

            def Result(self) -> str:
                return json.dumps({"text": "الجزء الأول"})

            def PartialResult(self) -> str:
                return json.dumps({"partial": "الجزء الجاري"})

        recognizer = PartialRecognizer({})
        with tempfile.TemporaryDirectory() as directory:
            engine = VoskSpeechEngine(
                model_directory=Path(directory),
                model=ModelDescriptor("linto", "test", "vosk"),
                supported_locale="aeb-TN",
                sample_rate_hz=16_000,
                channels=1,
                model_factory=lambda path: object(),
                recognizer_factory=cast(Any, lambda model, rate: recognizer),
            )
            session = engine.start_stream("aeb-TN", 16_000, 1)

            session.accept_pcm(b"\x01\x00" * 320)
            session.accept_pcm(b"\x02\x00" * 320)
            hypothesis = cast(Any, session).preview()

        self.assertEqual(hypothesis.text, "الجزء الأول الجزء الجاري")

    def test_rejects_invalid_decoder_json(self) -> None:
        class InvalidRecognizer(_Recognizer):
            def FinalResult(self) -> str:
                return "not-json"

        with tempfile.TemporaryDirectory() as directory:
            engine = VoskSpeechEngine(
                model_directory=Path(directory),
                model=ModelDescriptor("linto", "test", "vosk"),
                supported_locale="aeb-TN",
                sample_rate_hz=16_000,
                channels=1,
                model_factory=lambda path: object(),
                recognizer_factory=cast(
                    Any,
                    lambda model, rate: InvalidRecognizer({}),
                ),
            )

            with self.assertRaisesRegex(VoskRuntimeUnavailable, "invalid JSON"):
                engine.transcribe(_segment(), "aeb-TN")

    def test_rejects_noncanonical_audio_before_inference(self) -> None:
        calls = 0

        def recognizer_factory(model: Any, sample_rate_hz: float) -> _Recognizer:
            nonlocal calls
            del model, sample_rate_hz
            calls += 1
            return _Recognizer({"text": ""})

        with tempfile.TemporaryDirectory() as directory:
            engine = VoskSpeechEngine(
                model_directory=Path(directory),
                model=ModelDescriptor("linto", "test", "vosk"),
                supported_locale="aeb-TN",
                sample_rate_hz=16_000,
                channels=1,
                model_factory=lambda path: object(),
                recognizer_factory=recognizer_factory,
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

        self.assertEqual(calls, 0)


def _segment() -> SpeechSegment:
    return SpeechSegment(
        segment_id="speech:0-49",
        stream_id="speech",
        start_time_ms=0,
        end_time_ms=1_000,
        sample_rate_hz=16_000,
        channels=1,
        pcm_s16le=b"\x01\x00" * 16_000,
    )


if __name__ == "__main__":
    unittest.main()
