"""Transport-neutral orchestration of independent perception services."""

from __future__ import annotations

from collections.abc import Iterator

from aurisia.contracts import (
    AudioFrame,
    PerceptionEvent,
    TranscriptEvent,
    VoiceActivityState,
)
from aurisia.services.audio import AudioCaptureService
from aurisia.services.localization import LocalizationService
from aurisia.services.perception import PerceptionService
from aurisia.services.sound_detection import SoundDetectionService
from aurisia.services.speech import SpeechRecognitionService, SpeechRecognitionSession
from aurisia.services.vad import VadService


class PerceptionPipeline:
    """Connect services using contracts, without sharing implementation state.

    This composition is the in-process transport adapter. A local gRPC
    composition can replace it while preserving every service and event type.
    """

    def __init__(
        self,
        *,
        audio: AudioCaptureService,
        vad: VadService,
        speech: SpeechRecognitionService,
        sound: SoundDetectionService,
        localization: LocalizationService,
        perception: PerceptionService,
        speech_pre_roll_ms: int = 0,
        speech_partial_interval_ms: int = 0,
        speech_maximum_segment_ms: int = 0,
    ) -> None:
        if speech_pre_roll_ms < 0:
            raise ValueError("speech pre-roll must not be negative")
        if speech_partial_interval_ms < 0:
            raise ValueError("speech partial interval must not be negative")
        if speech_maximum_segment_ms < 0:
            raise ValueError("maximum speech segment must not be negative")
        self._audio = audio
        self._vad = vad
        self._speech = speech
        self._sound = sound
        self._localization = localization
        self._perception = perception
        self._speech_pre_roll_ms = speech_pre_roll_ms
        self._speech_partial_interval_ms = speech_partial_interval_ms
        self._speech_maximum_segment_ms = speech_maximum_segment_ms

    def run(self) -> Iterator[PerceptionEvent]:
        speech_session: SpeechRecognitionSession | None = None
        last_frame: AudioFrame | None = None
        last_preview_at_ms = 0

        for frame in self._audio.stream():
            last_frame = frame
            self._localization.observe(frame)

            for sound_event in self._sound.observe(frame):
                direction = self._localization.estimate(sound_event)
                yield self._perception.from_sound(sound_event, direction)

            activity = self._vad.observe(frame)
            if activity.state is VoiceActivityState.SPEECH_START:
                speech_session = self._speech.start_segment()
                for speech_frame in self._speech_start_frames(frame):
                    speech_session.accept(speech_frame)
                last_preview_at_ms = 0
            elif activity.state is VoiceActivityState.SPEECH_CONTINUE:
                if speech_session is None:
                    speech_session = self._speech.start_segment()
                    last_preview_at_ms = 0
                speech_session.accept(frame)
            elif (
                activity.state is VoiceActivityState.SPEECH_END
                and speech_session is not None
            ):
                transcript = speech_session.finish()
                if transcript is not None:
                    yield self._from_transcript(transcript)
                speech_session = None
                last_preview_at_ms = 0

            if (
                speech_session is not None
                and activity.state
                in {
                    VoiceActivityState.SPEECH_START,
                    VoiceActivityState.SPEECH_CONTINUE,
                }
            ):
                if (
                    self._speech_maximum_segment_ms > 0
                    and speech_session.duration_ms
                    >= self._speech_maximum_segment_ms
                ):
                    transcript = speech_session.finish()
                    if transcript is not None:
                        yield self._from_transcript(transcript)
                    speech_session = None
                    last_preview_at_ms = 0
                elif (
                    self._speech_partial_interval_ms > 0
                    and speech_session.duration_ms - last_preview_at_ms
                    >= self._speech_partial_interval_ms
                ):
                    last_preview_at_ms = speech_session.duration_ms
                    transcript = speech_session.preview()
                    if transcript is not None:
                        yield self._from_transcript(transcript)

        if last_frame is not None and speech_session is not None:
            self._vad.flush(
                last_frame.stream_id,
                last_frame.sequence,
                last_frame.end_time_ms,
            )
            transcript = speech_session.finish()
            if transcript is not None:
                yield self._from_transcript(transcript)

    def _from_transcript(self, transcript: TranscriptEvent) -> PerceptionEvent:
        direction = self._localization.estimate(transcript)
        return self._perception.from_transcript(transcript, direction)

    def _speech_start_frames(self, current: AudioFrame) -> list[AudioFrame]:
        ring_buffer = self._audio.ring_buffer
        if ring_buffer is None or self._speech_pre_roll_ms == 0:
            return [current]

        selected: list[AudioFrame] = []
        expected_sequence = current.sequence
        for candidate in reversed(ring_buffer.snapshot()):
            if candidate.stream_id != current.stream_id:
                continue
            if candidate.sequence > expected_sequence:
                continue
            if candidate.sequence != expected_sequence:
                break
            if current.captured_at_ms - candidate.captured_at_ms > self._speech_pre_roll_ms:
                break
            selected.append(candidate)
            expected_sequence -= 1
        if not selected or selected[0].sequence != current.sequence:
            return [current]
        selected.reverse()
        return selected
