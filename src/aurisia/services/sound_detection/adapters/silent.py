"""No-op sound engine for live plumbing before a classifier is installed."""

from __future__ import annotations

from collections.abc import Sequence

from aurisia.contracts import AudioFrame, ModelDescriptor

from ..ports import SoundHypothesis


class SilentSoundEngine:
    model = ModelDescriptor(
        model_id="development.silent-sound",
        version="1",
        runtime="python",
    )

    def classify(self, frame: AudioFrame) -> Sequence[SoundHypothesis]:
        del frame
        return ()
