"""Explicit, local-only microphone recording for ASR evaluation."""

from __future__ import annotations

import math
import os
import tempfile
import wave
from collections import deque
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from pathlib import Path
from typing import Protocol

from aurisia.contracts import AudioFrame, SpeechSegment, VoiceActivityState
from aurisia.services.vad import VadService

from .corpus import AsrCorpus, AsrEvaluationCase


class RecordingSource(Protocol):
    def frames(self) -> Iterator[AudioFrame]: ...

    def close(self) -> None: ...


@dataclass(frozen=True, slots=True)
class CorpusRecording:
    case_id: str
    path: Path
    duration_ms: int
    skipped_existing: bool


SourceFactory = Callable[[], RecordingSource]
VadFactory = Callable[[], VadService]
CasePrompt = Callable[[AsrEvaluationCase, int, int], None]
StatusSink = Callable[[str], None]


def record_corpus(
    corpus: AsrCorpus,
    output_directory: Path,
    *,
    source_factory: SourceFactory,
    vad_factory: VadFactory,
    prompt: CasePrompt,
    status_sink: StatusSink,
    pre_roll_ms: int,
    timeout_seconds: float,
    overwrite: bool = False,
) -> tuple[CorpusRecording, ...]:
    """Record one VAD-delimited canonical WAV for each corpus case."""

    if pre_roll_ms < 0:
        raise ValueError("pre-roll must not be negative")
    if not 2.0 <= timeout_seconds <= 30.0:
        raise ValueError("recording timeout must be between 2 and 30 seconds")
    output_directory.mkdir(parents=True, exist_ok=True)
    recordings: list[CorpusRecording] = []

    for index, case in enumerate(corpus.cases, start=1):
        path = output_directory / f"{case.case_id}.wav"
        if path.exists() and not overwrite:
            status_sink(f"Skipping existing recording: {path}")
            recordings.append(
                CorpusRecording(
                    case_id=case.case_id,
                    path=path,
                    duration_ms=_wave_duration_ms(path),
                    skipped_existing=True,
                )
            )
            continue

        prompt(case, index, len(corpus.cases))
        source = source_factory()
        try:
            segment = capture_speech_segment(
                source.frames(),
                vad_factory(),
                pre_roll_ms=pre_roll_ms,
                timeout_ms=round(timeout_seconds * 1_000),
                segment_id=case.case_id,
            )
        finally:
            source.close()
        _write_wave_atomically(path, segment)
        status_sink(f"Recorded {segment.end_time_ms - segment.start_time_ms} ms: {path}")
        recordings.append(
            CorpusRecording(
                case_id=case.case_id,
                path=path,
                duration_ms=segment.end_time_ms - segment.start_time_ms,
                skipped_existing=False,
            )
        )
    return tuple(recordings)


def capture_speech_segment(
    frames: Iterator[AudioFrame],
    vad: VadService,
    *,
    pre_roll_ms: int,
    timeout_ms: int,
    segment_id: str,
) -> SpeechSegment:
    """Capture the first complete utterance using a replaceable VAD service."""

    if pre_roll_ms < 0:
        raise ValueError("pre-roll must not be negative")
    if timeout_ms <= 0:
        raise ValueError("capture timeout must be positive")

    recent: deque[AudioFrame] = deque()
    speech_frames: list[AudioFrame] = []
    first_observed_ms: int | None = None

    for frame in frames:
        if first_observed_ms is None:
            first_observed_ms = frame.captured_at_ms
        recent.append(frame)
        while recent and frame.captured_at_ms - recent[0].captured_at_ms > pre_roll_ms:
            recent.popleft()

        activity = vad.observe(frame)
        if activity.state is VoiceActivityState.SPEECH_START:
            speech_frames = list(recent) if pre_roll_ms else [frame]
        elif activity.state is VoiceActivityState.SPEECH_CONTINUE and speech_frames:
            speech_frames.append(frame)
        elif activity.state is VoiceActivityState.SPEECH_END and speech_frames:
            return _segment_from_frames(speech_frames, segment_id)

        elapsed_ms = frame.end_time_ms - first_observed_ms
        if elapsed_ms >= timeout_ms:
            break

    if speech_frames:
        return _segment_from_frames(speech_frames, segment_id)
    raise RuntimeError(
        f"no speech was detected within {math.ceil(timeout_ms / 1_000)} seconds"
    )


def _segment_from_frames(frames: list[AudioFrame], segment_id: str) -> SpeechSegment:
    first = frames[0]
    last = frames[-1]
    if any(
        frame.stream_id != first.stream_id
        or frame.sample_rate_hz != first.sample_rate_hz
        or frame.channels != first.channels
        for frame in frames
    ):
        raise ValueError("recording audio format changed within an utterance")
    return SpeechSegment(
        segment_id=segment_id,
        stream_id=first.stream_id,
        start_time_ms=first.captured_at_ms,
        end_time_ms=last.end_time_ms,
        sample_rate_hz=first.sample_rate_hz,
        channels=first.channels,
        pcm_s16le=b"".join(frame.pcm_s16le for frame in frames),
    )


def _write_wave_atomically(path: Path, segment: SpeechSegment) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary_name = tempfile.mkstemp(
        prefix=f".{path.stem}-",
        suffix=".wav.tmp",
        dir=path.parent,
    )
    os.close(descriptor)
    temporary_path = Path(temporary_name)
    try:
        with wave.open(str(temporary_path), "wb") as output:
            output.setnchannels(segment.channels)
            output.setsampwidth(2)
            output.setframerate(segment.sample_rate_hz)
            output.writeframes(segment.pcm_s16le)
        temporary_path.replace(path)
    finally:
        temporary_path.unlink(missing_ok=True)


def _wave_duration_ms(path: Path) -> int:
    try:
        with wave.open(str(path), "rb") as recording:
            if recording.getframerate() <= 0:
                raise ValueError(f"invalid WAV sample rate: {path}")
            return round(recording.getnframes() * 1_000 / recording.getframerate())
    except (OSError, wave.Error) as exc:
        raise ValueError(f"cannot inspect existing recording {path}: {exc}") from exc
