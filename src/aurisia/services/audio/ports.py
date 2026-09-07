"""Ports owned by the audio capture service."""

from __future__ import annotations

from collections.abc import Iterable
from typing import Protocol

from aurisia.contracts import AudioFrame


class AudioSource(Protocol):
    """Platform-specific source of standardized PCM frames."""

    def frames(self) -> Iterable[AudioFrame]:
        """Yield ordered audio frames until the source stops."""

        ...
