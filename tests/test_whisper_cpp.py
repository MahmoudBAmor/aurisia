from __future__ import annotations

import hashlib
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path
from typing import Any
from unittest.mock import Mock

from aurisia.contracts import ModelDescriptor, SpeechSegment
from aurisia.services.speech import SpeechInferenceMeasurement
from aurisia.services.speech.adapters import (
    WhisperCppSpeechEngine,
    WhisperServiceUnavailable,
    verify_whisper_runtime,
)


class WhisperCppSpeechEngineTests(unittest.TestCase):
    def test_transcribes_canonical_audio_through_in_memory_request(self) -> None:
        observed: dict[str, Any] = {}
        measurements: list[SpeechInferenceMeasurement] = []

        def request(
            endpoint: str,
            body: bytes,
            content_type: str,
            timeout_seconds: float,
        ) -> bytes:
            observed.update(
                endpoint=endpoint,
                body=body,
                content_type=content_type,
                timeout_seconds=timeout_seconds,
            )
            return (
                b'{"text":"\\u0646\\u062d\\u0628 \\u0646\\u0645\\u0634\\u064a '
                b'\\u063a\\u062f\\u0648\\u0629"}'
            )

        engine = _engine(
            request_inference=request,
            measurement_sink=measurements.append,
        )

        hypothesis = engine.transcribe(_segment(), "aeb-TN")

        self.assertEqual(hypothesis.text, "نحب نمشي غدوة")
        self.assertIsNone(hypothesis.confidence)
        self.assertEqual(observed["endpoint"], "127.0.0.1:50052")
        self.assertEqual(observed["timeout_seconds"], 10.0)
        self.assertIn("multipart/form-data; boundary=", observed["content_type"])
        body = observed["body"]
        self.assertIn(b"RIFF", body)
        self.assertIn(b"WAVE", body)
        self.assertIn(b'name="language"', body)
        self.assertIn(b"\r\nar\r\n", body)
        self.assertEqual(len(measurements), 1)
        self.assertEqual(measurements[0].audio_duration_ms, 1_000)
        self.assertGreaterEqual(measurements[0].inference_latency_ms, 0.0)

    def test_rejects_noncanonical_audio_before_inference(self) -> None:
        request = Mock()
        engine = _engine(request_inference=request)
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

        request.assert_not_called()

    def test_rejects_invalid_server_response(self) -> None:
        def request(
            endpoint: str,
            body: bytes,
            content_type: str,
            timeout_seconds: float,
        ) -> bytes:
            del endpoint, body, content_type, timeout_seconds
            return b"not JSON"

        with self.assertRaisesRegex(WhisperServiceUnavailable, "invalid JSON"):
            _engine(request_inference=request).transcribe(_segment(), "aeb-TN")

    def test_rejects_a_modified_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "whisper-server.exe"
            executable.write_bytes(b"modified")

            with self.assertRaisesRegex(WhisperServiceUnavailable, "checksum mismatch"):
                verify_whisper_runtime(executable, "0" * 64)

    def test_accepts_a_verified_runtime(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            executable = Path(directory) / "whisper-server.exe"
            executable.write_bytes(b"verified runtime")
            checksum = hashlib.sha256(executable.read_bytes()).hexdigest()

            verify_whisper_runtime(executable, checksum)


def _engine(
    *,
    request_inference: Callable[[str, bytes, str, float], bytes] | None = None,
    measurement_sink: Callable[[SpeechInferenceMeasurement], None] | None = None,
) -> WhisperCppSpeechEngine:
    return WhisperCppSpeechEngine(
        endpoint="127.0.0.1:50052",
        model=ModelDescriptor("whisper", "test", "whisper.cpp/test"),
        language="ar",
        supported_locale="aeb-TN",
        sample_rate_hz=16_000,
        channels=1,
        timeout_seconds=10,
        request_inference=request_inference,
        measurement_sink=measurement_sink,
    )


def _segment() -> SpeechSegment:
    return SpeechSegment(
        segment_id="speech:0-49",
        stream_id="speech",
        start_time_ms=0,
        end_time_ms=1_000,
        sample_rate_hz=16_000,
        channels=1,
        pcm_s16le=b"\x00\x00" * 16_000,
    )


if __name__ == "__main__":
    unittest.main()
