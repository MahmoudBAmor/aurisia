"""Replay a local corpus through the configured speech service."""

from __future__ import annotations

import time
import wave
from collections.abc import Iterator
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Protocol

from aurisia.contracts import AudioFrame, ModelDescriptor, SpeechSegment, TranscriptEvent

from .corpus import AsrCorpus
from .metrics import character_error, retained_code_switch_terms, word_error


class SpeechRecognizer(Protocol):
    @property
    def model(self) -> ModelDescriptor: ...

    def recognize(self, segment: SpeechSegment) -> TranscriptEvent | None: ...

    def start_segment(self) -> SpeechRecognitionSession: ...


class SpeechRecognitionSession(Protocol):
    def accept(self, frame: AudioFrame) -> None: ...

    def finish(self) -> TranscriptEvent | None: ...


@dataclass(frozen=True, slots=True)
class AsrCaseResult:
    case_id: str
    reference_arabic: str
    raw_transcript: str
    display_transcript: str
    audio_duration_ms: int
    recognition_latency_ms: float
    finalization_latency_ms: float
    real_time_factor: float
    word_edits: int
    reference_words: int
    character_edits: int
    reference_characters: int
    retained_code_switch_terms: int
    reference_code_switch_terms: int

    @property
    def word_error_rate(self) -> float:
        return self.word_edits / self.reference_words

    @property
    def character_error_rate(self) -> float:
        return self.character_edits / self.reference_characters


@dataclass(frozen=True, slots=True)
class AsrEvaluationReport:
    corpus_id: str
    corpus_version: str
    locale: str
    measured_at: str
    model: ModelDescriptor
    cases: tuple[AsrCaseResult, ...]

    @property
    def word_error_rate(self) -> float:
        return sum(case.word_edits for case in self.cases) / sum(
            case.reference_words for case in self.cases
        )

    @property
    def character_error_rate(self) -> float:
        return sum(case.character_edits for case in self.cases) / sum(
            case.reference_characters for case in self.cases
        )

    @property
    def code_switch_retention_rate(self) -> float | None:
        reference_count = sum(
            case.reference_code_switch_terms for case in self.cases
        )
        if reference_count == 0:
            return None
        return (
            sum(case.retained_code_switch_terms for case in self.cases)
            / reference_count
        )

    @property
    def mean_recognition_latency_ms(self) -> float:
        return sum(case.recognition_latency_ms for case in self.cases) / len(
            self.cases
        )

    @property
    def maximum_recognition_latency_ms(self) -> float:
        return max(case.recognition_latency_ms for case in self.cases)

    @property
    def mean_finalization_latency_ms(self) -> float:
        return sum(case.finalization_latency_ms for case in self.cases) / len(
            self.cases
        )

    @property
    def maximum_finalization_latency_ms(self) -> float:
        return max(case.finalization_latency_ms for case in self.cases)

    def to_dict(self) -> dict[str, Any]:
        summary: dict[str, Any] = {
            "word_error_rate": self.word_error_rate,
            "character_error_rate": self.character_error_rate,
            "code_switch_retention_rate": self.code_switch_retention_rate,
            "mean_recognition_latency_ms": self.mean_recognition_latency_ms,
            "maximum_recognition_latency_ms": self.maximum_recognition_latency_ms,
            "mean_finalization_latency_ms": self.mean_finalization_latency_ms,
            "maximum_finalization_latency_ms": self.maximum_finalization_latency_ms,
        }
        return {
            "schema_version": 2,
            "corpus_id": self.corpus_id,
            "corpus_version": self.corpus_version,
            "locale": self.locale,
            "measured_at": self.measured_at,
            "model": {
                "model_id": self.model.model_id,
                "version": self.model.version,
                "runtime": self.model.runtime,
            },
            "summary": summary,
            "cases": [
                {
                    "case_id": case.case_id,
                    "reference_arabic": case.reference_arabic,
                    "raw_transcript": case.raw_transcript,
                    "display_transcript": case.display_transcript,
                    "audio_duration_ms": case.audio_duration_ms,
                    "recognition_latency_ms": case.recognition_latency_ms,
                    "finalization_latency_ms": case.finalization_latency_ms,
                    "real_time_factor": case.real_time_factor,
                    "word_error_rate": case.word_error_rate,
                    "character_error_rate": case.character_error_rate,
                    "retained_code_switch_terms": case.retained_code_switch_terms,
                    "reference_code_switch_terms": case.reference_code_switch_terms,
                }
                for case in self.cases
            ],
        }


def evaluate_asr_corpus(
    corpus: AsrCorpus,
    audio_directory: Path,
    speech: SpeechRecognizer,
) -> AsrEvaluationReport:
    """Evaluate a persistent recognizer against local canonical recordings."""

    results: list[AsrCaseResult] = []
    for case in corpus.cases:
        segment = _load_wave_segment(
            audio_directory / f"{case.case_id}.wav",
            case.case_id,
        )
        transcript, latency_ms, finalization_latency_ms = _recognize_stream(
            speech,
            segment,
        )
        raw_text = transcript.raw_text if transcript is not None else ""
        display_text = transcript.display_text if transcript is not None else ""
        word_metric = word_error(case.reference_arabic, display_text)
        character_metric = character_error(case.reference_arabic, display_text)
        retained_terms = retained_code_switch_terms(
            f"{raw_text} {display_text}",
            case.code_switch_terms,
        )
        duration_ms = segment.end_time_ms - segment.start_time_ms
        results.append(
            AsrCaseResult(
                case_id=case.case_id,
                reference_arabic=case.reference_arabic,
                raw_transcript=raw_text,
                display_transcript=display_text,
                audio_duration_ms=duration_ms,
                recognition_latency_ms=latency_ms,
                finalization_latency_ms=finalization_latency_ms,
                real_time_factor=latency_ms / duration_ms,
                word_edits=word_metric.edit_distance,
                reference_words=word_metric.reference_units,
                character_edits=character_metric.edit_distance,
                reference_characters=character_metric.reference_units,
                retained_code_switch_terms=retained_terms,
                reference_code_switch_terms=len(case.code_switch_terms),
            )
        )
    return AsrEvaluationReport(
        corpus_id=corpus.corpus_id,
        corpus_version=corpus.version,
        locale=corpus.locale,
        measured_at=datetime.now(timezone.utc).isoformat(),
        model=speech.model,
        cases=tuple(results),
    )


def _recognize_stream(
    speech: SpeechRecognizer,
    segment: SpeechSegment,
) -> tuple[TranscriptEvent | None, float, float]:
    """Replay frames incrementally and distinguish total work from finalization."""

    session = speech.start_segment()
    started_ns = time.perf_counter_ns()
    for frame in _segment_frames(segment):
        session.accept(frame)
    finalization_started_ns = time.perf_counter_ns()
    transcript = session.finish()
    finished_ns = time.perf_counter_ns()
    return (
        transcript,
        (finished_ns - started_ns) / 1_000_000,
        (finished_ns - finalization_started_ns) / 1_000_000,
    )


def _segment_frames(
    segment: SpeechSegment,
    *,
    frame_duration_ms: int = 20,
) -> Iterator[AudioFrame]:
    bytes_per_sample = 2 * segment.channels
    sample_count = len(segment.pcm_s16le) // bytes_per_sample
    samples_per_frame = segment.sample_rate_hz * frame_duration_ms // 1_000
    for sequence, sample_offset in enumerate(range(0, sample_count, samples_per_frame)):
        end_offset = min(sample_count, sample_offset + samples_per_frame)
        yield AudioFrame(
            stream_id=segment.stream_id,
            sequence=sequence,
            captured_at_ms=round(sample_offset * 1_000 / segment.sample_rate_hz),
            sample_rate_hz=segment.sample_rate_hz,
            channels=segment.channels,
            pcm_s16le=segment.pcm_s16le[
                sample_offset * bytes_per_sample : end_offset * bytes_per_sample
            ],
        )


def _load_wave_segment(path: Path, case_id: str) -> SpeechSegment:
    try:
        with wave.open(str(path), "rb") as recording:
            if recording.getcomptype() != "NONE":
                raise ValueError(f"recording must be uncompressed PCM: {path}")
            if recording.getsampwidth() != 2:
                raise ValueError(f"recording must use signed 16-bit PCM: {path}")
            sample_rate_hz = recording.getframerate()
            channels = recording.getnchannels()
            sample_count = recording.getnframes()
            pcm = recording.readframes(sample_count)
    except (OSError, wave.Error) as exc:
        raise ValueError(f"cannot read corpus recording {path}: {exc}") from exc
    if sample_rate_hz <= 0 or channels <= 0 or sample_count <= 0:
        raise ValueError(f"corpus recording is empty or invalid: {path}")
    duration_ms = round(sample_count * 1_000 / sample_rate_hz)
    return SpeechSegment(
        segment_id=f"evaluation:{case_id}",
        stream_id=f"corpus:{case_id}",
        start_time_ms=0,
        end_time_ms=duration_ms,
        sample_rate_hz=sample_rate_hz,
        channels=channels,
        pcm_s16le=pcm,
    )
