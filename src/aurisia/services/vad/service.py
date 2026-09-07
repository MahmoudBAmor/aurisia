"""Voice activity detection application service."""

from __future__ import annotations

from aurisia.contracts import AudioFrame, ModelDescriptor, VoiceActivity, VoiceActivityState

from .ports import VadEngine


class VadService:
    """Convert model probabilities into stable speech state transitions."""

    service_name = "vad"

    def __init__(
        self,
        engine: VadEngine,
        *,
        start_threshold: float = 0.6,
        end_threshold: float = 0.35,
        end_silence_frames: int = 3,
    ) -> None:
        if not 0.0 <= end_threshold <= start_threshold <= 1.0:
            raise ValueError("VAD thresholds must satisfy 0 <= end <= start <= 1")
        if end_silence_frames <= 0:
            raise ValueError("end_silence_frames must be positive")
        self._engine = engine
        self._start_threshold = start_threshold
        self._end_threshold = end_threshold
        self._end_silence_frames = end_silence_frames
        self._active = False
        self._silence_frames = 0
        self._last_probability = 0.0

    @property
    def model(self) -> ModelDescriptor:
        return self._engine.model

    def observe(self, frame: AudioFrame) -> VoiceActivity:
        probability = self._engine.speech_probability(frame)
        if probability is None:
            return VoiceActivity(
                stream_id=frame.stream_id,
                frame_sequence=frame.sequence,
                state=(
                    VoiceActivityState.SPEECH_CONTINUE
                    if self._active
                    else VoiceActivityState.SILENCE
                ),
                probability=self._last_probability,
                observed_at_ms=frame.captured_at_ms,
            )
        if not 0.0 <= probability <= 1.0:
            raise ValueError("VAD engine returned a probability outside [0, 1]")
        self._last_probability = probability

        if not self._active:
            if probability >= self._start_threshold:
                self._active = True
                self._silence_frames = 0
                state = VoiceActivityState.SPEECH_START
            else:
                state = VoiceActivityState.SILENCE
        elif probability >= self._end_threshold:
            self._silence_frames = 0
            state = VoiceActivityState.SPEECH_CONTINUE
        else:
            self._silence_frames += 1
            if self._silence_frames >= self._end_silence_frames:
                self._active = False
                self._silence_frames = 0
                state = VoiceActivityState.SPEECH_END
            else:
                state = VoiceActivityState.SPEECH_CONTINUE

        return VoiceActivity(
            stream_id=frame.stream_id,
            frame_sequence=frame.sequence,
            state=state,
            probability=probability,
            observed_at_ms=frame.captured_at_ms,
        )

    def flush(
        self,
        stream_id: str,
        frame_sequence: int,
        observed_at_ms: int,
    ) -> VoiceActivity | None:
        if not self._active:
            return None
        self._active = False
        self._silence_frames = 0
        self._last_probability = 0.0
        return VoiceActivity(
            stream_id=stream_id,
            frame_sequence=frame_sequence,
            state=VoiceActivityState.SPEECH_END,
            probability=0.0,
            observed_at_ms=observed_at_ms,
        )
