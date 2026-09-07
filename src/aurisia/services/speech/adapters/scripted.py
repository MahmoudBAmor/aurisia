"""Deterministic Tunisian transcript adapter for the first vertical slice."""

from __future__ import annotations

from collections.abc import Iterable

from aurisia.contracts import ModelDescriptor, SpeechSegment

from ..ports import SpeechHypothesis


class ScriptedSpeechEngine:
    model = ModelDescriptor(
        model_id="development.scripted-aeb-tn",
        version="1",
        runtime="python",
    )

    def __init__(self, transcripts: Iterable[str], *, repeat: bool = False) -> None:
        self._transcripts = tuple(transcripts)
        if not self._transcripts:
            raise ValueError("at least one scripted transcript is required")
        self._repeat = repeat
        self._index = 0

    def transcribe(self, segment: SpeechSegment, locale: str) -> SpeechHypothesis:
        del segment
        if locale != "aeb-TN":
            raise ValueError("the scripted adapter only supports aeb-TN")
        if self._index >= len(self._transcripts) and not self._repeat:
            raise RuntimeError("the scripted speech adapter has no transcript left")
        transcript = self._transcripts[self._index % len(self._transcripts)]
        self._index += 1
        return SpeechHypothesis(
            text=transcript,
            confidence=0.92,
        )
