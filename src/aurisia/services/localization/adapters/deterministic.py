"""Repeatable direction simulator used until microphone-array hardware exists."""

from __future__ import annotations

import hashlib

from aurisia.contracts import AudioFrame, Direction, ModelDescriptor

from ..ports import LocalizationHypothesis


class DeterministicDirectionEngine:
    model = ModelDescriptor(
        model_id="development.deterministic-direction",
        version="1",
        runtime="python",
    )
    _directions = (
        (Direction.LEFT, -60.0),
        (Direction.CENTER, 0.0),
        (Direction.RIGHT, 60.0),
    )

    def observe(self, frame: AudioFrame) -> None:
        del frame

    def estimate(
        self,
        source_event_id: str,
        start_time_ms: int,
        end_time_ms: int,
    ) -> LocalizationHypothesis:
        del start_time_ms, end_time_ms
        digest = hashlib.blake2s(source_event_id.encode("utf-8"), digest_size=1).digest()
        direction, angle = self._directions[digest[0] % len(self._directions)]
        return LocalizationHypothesis(
            direction=direction,
            angle_degrees=angle,
            confidence=1.0,
        )
