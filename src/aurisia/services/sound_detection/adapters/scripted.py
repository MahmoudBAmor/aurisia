"""Deterministic sound classifier for the first vertical slice."""

from __future__ import annotations

from collections.abc import Mapping, Sequence

from aurisia.contracts import AudioFrame, ModelDescriptor

from ..ports import SoundHypothesis


class ScriptedSoundEngine:
    model = ModelDescriptor(
        model_id="development.scripted-sound",
        version="1",
        runtime="python",
    )

    def __init__(self, schedule: Mapping[int, Sequence[SoundHypothesis]]) -> None:
        self._schedule = {sequence: tuple(hypotheses) for sequence, hypotheses in schedule.items()}

    def classify(self, frame: AudioFrame) -> Sequence[SoundHypothesis]:
        return self._schedule.get(frame.sequence, ())
