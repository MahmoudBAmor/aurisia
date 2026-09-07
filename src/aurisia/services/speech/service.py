"""Speech recognition application service."""

from __future__ import annotations

from typing import cast

from aurisia.contracts import AudioFrame, ModelDescriptor, SpeechSegment, TranscriptEvent

from .ports import (
    PreviewingSpeechSession,
    SpeechEngine,
    SpeechHypothesis,
    StreamingSpeechEngine,
    StreamingSpeechSession,
    TextDisplayNormalizer,
)


class SpeechRecognitionService:
    service_name = "speech_recognition"

    def __init__(
        self,
        engine: SpeechEngine,
        normalizer: TextDisplayNormalizer,
        *,
        locale: str,
        minimum_segment_ms: int = 0,
    ) -> None:
        if not locale:
            raise ValueError("locale must not be empty")
        if minimum_segment_ms < 0:
            raise ValueError("minimum speech segment duration must not be negative")
        self._engine = engine
        self._normalizer = normalizer
        self._locale = locale
        self._minimum_segment_ms = minimum_segment_ms
        self._streaming_engine = (
            engine if isinstance(engine, StreamingSpeechEngine) else None
        )

    @property
    def model(self) -> ModelDescriptor:
        return self._engine.model

    def recognize(self, segment: SpeechSegment) -> TranscriptEvent | None:
        if segment.end_time_ms - segment.start_time_ms < self._minimum_segment_ms:
            return None
        hypothesis = self._engine.transcribe(segment, self._locale)
        return self._to_event(
            segment_id=segment.segment_id,
            stream_id=segment.stream_id,
            start_time_ms=segment.start_time_ms,
            end_time_ms=segment.end_time_ms,
            hypothesis=hypothesis,
        )

    def start_segment(self) -> SpeechRecognitionSession:
        """Create isolated state for one VAD-delimited utterance."""

        return SpeechRecognitionSession(self)

    def _to_event(
        self,
        *,
        segment_id: str,
        stream_id: str,
        start_time_ms: int,
        end_time_ms: int,
        hypothesis: SpeechHypothesis,
        is_final: bool = True,
    ) -> TranscriptEvent | None:
        raw_text = hypothesis.text.strip()
        if not raw_text:
            return None
        return TranscriptEvent(
            event_id=f"transcript:{segment_id}",
            stream_id=stream_id,
            start_time_ms=start_time_ms,
            end_time_ms=end_time_ms,
            raw_text=raw_text,
            display_text=self._normalizer.normalize(raw_text),
            locale=self._locale,
            confidence=hypothesis.confidence,
            is_final=is_final,
            model=self._engine.model,
        )


class SpeechRecognitionSession:
    """Bridge streaming and complete-segment engines behind one service API."""

    def __init__(self, service: SpeechRecognitionService) -> None:
        self._service = service
        self._first: AudioFrame | None = None
        self._last: AudioFrame | None = None
        self._pcm_chunks: list[bytes] = []
        self._streaming_session: StreamingSpeechSession | None = None
        self._finished = False
        self._last_preview_text = ""

    def accept(self, frame: AudioFrame) -> None:
        if self._finished:
            raise RuntimeError("speech recognition session is already finished")
        if self._first is None:
            self._first = frame
        else:
            assert self._last is not None
            if (
                frame.stream_id != self._first.stream_id
                or frame.sample_rate_hz != self._first.sample_rate_hz
                or frame.channels != self._first.channels
            ):
                raise ValueError("speech audio format changed within a segment")
            if frame.sequence != self._last.sequence + 1:
                raise ValueError("speech audio frames must be contiguous")
            if frame.captured_at_ms < self._last.captured_at_ms:
                raise ValueError("speech audio timestamps must be monotonic")
        self._last = frame

        if self._streaming_session is not None:
            self._streaming_session.accept_pcm(frame.pcm_s16le)
            return
        self._pcm_chunks.append(frame.pcm_s16le)
        if (
            self._service._streaming_engine is not None
            and self._duration_ms >= self._service._minimum_segment_ms
        ):
            self._streaming_session = self._service._streaming_engine.start_stream(
                self._service._locale,
                frame.sample_rate_hz,
                frame.channels,
            )
            for pcm in self._pcm_chunks:
                self._streaming_session.accept_pcm(pcm)
            self._pcm_chunks.clear()

    def finish(self) -> TranscriptEvent | None:
        if self._finished:
            raise RuntimeError("speech recognition session is already finished")
        self._finished = True
        if self._first is None or self._last is None:
            raise RuntimeError("cannot finish an empty speech recognition session")
        if self._duration_ms < self._service._minimum_segment_ms:
            return None

        segment_id = f"{self._first.stream_id}:{self._first.sequence}"
        if self._streaming_session is not None:
            hypothesis = self._streaming_session.finish(self._duration_ms)
        else:
            segment = SpeechSegment(
                segment_id=segment_id,
                stream_id=self._first.stream_id,
                start_time_ms=self._first.captured_at_ms,
                end_time_ms=self._last.end_time_ms,
                sample_rate_hz=self._first.sample_rate_hz,
                channels=self._first.channels,
                pcm_s16le=b"".join(self._pcm_chunks),
            )
            hypothesis = self._service._engine.transcribe(
                segment,
                self._service._locale,
            )
        return self._service._to_event(
            segment_id=segment_id,
            stream_id=self._first.stream_id,
            start_time_ms=self._first.captured_at_ms,
            end_time_ms=self._last.end_time_ms,
            hypothesis=hypothesis,
        )

    def preview(self) -> TranscriptEvent | None:
        """Return a changed non-final transcript when the adapter supports it."""

        if self._finished:
            raise RuntimeError("speech recognition session is already finished")
        if self._first is None or self._last is None:
            raise RuntimeError("cannot preview an empty speech recognition session")
        session = self._streaming_session
        if session is None or not hasattr(session, "preview"):
            return None
        hypothesis = cast(PreviewingSpeechSession, session).preview()
        preview_text = hypothesis.text.strip()
        if not preview_text or preview_text == self._last_preview_text:
            return None
        self._last_preview_text = preview_text
        return self._service._to_event(
            segment_id=f"{self._first.stream_id}:{self._first.sequence}",
            stream_id=self._first.stream_id,
            start_time_ms=self._first.captured_at_ms,
            end_time_ms=self._last.end_time_ms,
            hypothesis=hypothesis,
            is_final=False,
        )

    @property
    def duration_ms(self) -> int:
        if self._first is None or self._last is None:
            return 0
        return self._last.end_time_ms - self._first.captured_at_ms

    @property
    def _duration_ms(self) -> int:
        return self.duration_ms
