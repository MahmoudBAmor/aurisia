from __future__ import annotations

import unittest

from aurisia.contracts import AudioFrame, ModelDescriptor, SpeechSegment
from aurisia.services.speech import SpeechRecognitionService
from aurisia.services.speech.ports import SpeechHypothesis


class _SpeechEngine:
    model = ModelDescriptor("test-speech", "1", "test")

    def __init__(self, text: str) -> None:
        self._text = text
        self.calls = 0

    def transcribe(self, segment: SpeechSegment, locale: str) -> SpeechHypothesis:
        del segment, locale
        self.calls += 1
        return SpeechHypothesis(self._text, None)


class _IdentityNormalizer:
    def normalize(self, text: str) -> str:
        return text


class _StreamingSession:
    def __init__(self, text: str) -> None:
        self._text = text
        self.chunks: list[bytes] = []
        self.finished_durations: list[int] = []

    def accept_pcm(self, pcm_s16le: bytes) -> None:
        self.chunks.append(pcm_s16le)

    def finish(self, audio_duration_ms: int) -> SpeechHypothesis:
        self.finished_durations.append(audio_duration_ms)
        return SpeechHypothesis(self._text, 0.9)

    def preview(self) -> SpeechHypothesis:
        return SpeechHypothesis(self._text, None)


class _StreamingEngine(_SpeechEngine):
    def __init__(self, text: str) -> None:
        super().__init__(text)
        self.sessions: list[_StreamingSession] = []
        self.stream_contracts: list[tuple[str, int, int]] = []

    def start_stream(
        self,
        locale: str,
        sample_rate_hz: int,
        channels: int,
    ) -> _StreamingSession:
        self.stream_contracts.append((locale, sample_rate_hz, channels))
        session = _StreamingSession(self._text)
        self.sessions.append(session)
        return session


class SpeechRecognitionServiceTests(unittest.TestCase):
    def test_skips_short_vad_false_positive_before_model_inference(self) -> None:
        engine = _SpeechEngine("نص")
        service = SpeechRecognitionService(
            engine,
            _IdentityNormalizer(),
            locale="aeb-TN",
            minimum_segment_ms=300,
        )

        transcript = service.recognize(_segment(duration_ms=200))

        self.assertIsNone(transcript)
        self.assertEqual(engine.calls, 0)

    def test_empty_decoder_result_is_not_an_application_error(self) -> None:
        engine = _SpeechEngine("")
        service = SpeechRecognitionService(
            engine,
            _IdentityNormalizer(),
            locale="aeb-TN",
        )

        transcript = service.recognize(_segment(duration_ms=500))

        self.assertIsNone(transcript)
        self.assertEqual(engine.calls, 1)

    def test_streaming_session_amortizes_inference_while_frames_arrive(self) -> None:
        engine = _StreamingEngine("نص")
        service = SpeechRecognitionService(
            engine,
            _IdentityNormalizer(),
            locale="aeb-TN",
            minimum_segment_ms=40,
        )
        session = service.start_segment()
        frames = [_frame(sequence) for sequence in range(3)]

        session.accept(frames[0])
        self.assertEqual(engine.sessions, [])
        session.accept(frames[1])
        self.assertEqual(engine.sessions[0].chunks, [frames[0].pcm_s16le, frames[1].pcm_s16le])
        session.accept(frames[2])
        transcript = session.finish()

        self.assertEqual(engine.calls, 0)
        self.assertEqual(engine.stream_contracts, [("aeb-TN", 16_000, 1)])
        self.assertEqual(engine.sessions[0].chunks, [frame.pcm_s16le for frame in frames])
        self.assertEqual(engine.sessions[0].finished_durations, [60])
        self.assertIsNotNone(transcript)
        assert transcript is not None
        self.assertEqual(transcript.raw_text, "نص")
        self.assertEqual(transcript.event_id, "transcript:speech:0")

    def test_partial_transcript_updates_use_one_stable_event_identity(self) -> None:
        engine = _StreamingEngine("نص جزئي")
        service = SpeechRecognitionService(
            engine,
            _IdentityNormalizer(),
            locale="aeb-TN",
            minimum_segment_ms=40,
        )
        session = service.start_segment()
        session.accept(_frame(0))
        session.accept(_frame(1))

        first_preview = session.preview()
        duplicate_preview = session.preview()
        session.accept(_frame(2))
        final = session.finish()

        self.assertIsNotNone(first_preview)
        assert first_preview is not None
        self.assertFalse(first_preview.is_final)
        self.assertIsNone(duplicate_preview)
        self.assertIsNotNone(final)
        assert final is not None
        self.assertTrue(final.is_final)
        self.assertEqual(first_preview.event_id, final.event_id)
        self.assertEqual(first_preview.event_id, "transcript:speech:0")

    def test_short_streaming_false_positive_never_starts_decoder(self) -> None:
        engine = _StreamingEngine("نص")
        service = SpeechRecognitionService(
            engine,
            _IdentityNormalizer(),
            locale="aeb-TN",
            minimum_segment_ms=40,
        )
        session = service.start_segment()
        session.accept(_frame(0))

        transcript = session.finish()

        self.assertIsNone(transcript)
        self.assertEqual(engine.sessions, [])
        self.assertEqual(engine.calls, 0)


def _segment(*, duration_ms: int) -> SpeechSegment:
    sample_count = 16_000 * duration_ms // 1_000
    return SpeechSegment(
        segment_id="speech:0-1",
        stream_id="speech",
        start_time_ms=0,
        end_time_ms=duration_ms,
        sample_rate_hz=16_000,
        channels=1,
        pcm_s16le=b"\x00\x00" * sample_count,
    )


def _frame(sequence: int) -> AudioFrame:
    return AudioFrame(
        stream_id="speech",
        sequence=sequence,
        captured_at_ms=sequence * 20,
        sample_rate_hz=16_000,
        channels=1,
        pcm_s16le=bytes([sequence, 0]) * 320,
    )


if __name__ == "__main__":
    unittest.main()
