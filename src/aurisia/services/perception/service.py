"""Fuse model-neutral observations into renderer-facing perception events."""

from __future__ import annotations

from aurisia.contracts import (
    DirectionEstimate,
    PerceptionEvent,
    PerceptionKind,
    Priority,
    SoundEvent,
    TranscriptEvent,
)


class PerceptionService:
    service_name = "perception"

    _sound_visuals = {
        "sound.vehicle.bus": ("🚌", Priority.VEHICLE, "#F59E0B"),
        "sound.vehicle.car": ("🚗", Priority.VEHICLE, "#F59E0B"),
        "sound.vehicle.motorcycle": ("🏍", Priority.VEHICLE, "#F59E0B"),
        "sound.alert.doorbell": ("🔔", Priority.ATTENTION, "#FACC15"),
        "sound.alert.alarm": ("🚨", Priority.DANGER, "#EF4444"),
        "sound.alert.siren": ("🚨", Priority.DANGER, "#EF4444"),
        "sound.alert.smoke_detector": ("🚨", Priority.DANGER, "#EF4444"),
        "sound.human.baby_cry": ("👶", Priority.ATTENTION, "#FACC15"),
        "sound.animal.dog": ("🐕", Priority.INFORMATION, "#3B82F6"),
        "sound.impact.glass_breaking": ("🪟", Priority.DANGER, "#EF4444"),
    }

    def __init__(self, *, event_lifetime_ms: int) -> None:
        if event_lifetime_ms <= 0:
            raise ValueError("event_lifetime_ms must be positive")
        self._event_lifetime_ms = event_lifetime_ms

    def from_transcript(
        self,
        transcript: TranscriptEvent,
        direction: DirectionEstimate,
    ) -> PerceptionEvent:
        _ensure_matching_direction(transcript.event_id, direction)
        return PerceptionEvent(
            event_id=f"perception:{transcript.event_id}",
            source_event_id=transcript.event_id,
            kind=PerceptionKind.SPEECH,
            title=transcript.display_text,
            icon="👤",
            priority=Priority.CONVERSATION,
            color="#22C55E",
            direction=direction.direction,
            start_time_ms=transcript.start_time_ms,
            end_time_ms=transcript.end_time_ms,
            lifetime_ms=self._event_lifetime_ms,
            confidence=transcript.confidence,
        )

    def from_sound(
        self,
        sound: SoundEvent,
        direction: DirectionEstimate,
    ) -> PerceptionEvent:
        _ensure_matching_direction(sound.event_id, direction)
        try:
            icon, priority, color = self._sound_visuals[sound.label]
        except KeyError as exc:
            raise ValueError(f"no perception policy for {sound.label!r}") from exc
        return PerceptionEvent(
            event_id=f"perception:{sound.event_id}",
            source_event_id=sound.event_id,
            kind=PerceptionKind.SOUND,
            title=sound.display_label,
            icon=icon,
            priority=priority,
            color=color,
            direction=direction.direction,
            start_time_ms=sound.start_time_ms,
            end_time_ms=sound.end_time_ms,
            lifetime_ms=self._event_lifetime_ms,
            confidence=sound.confidence,
        )


def _ensure_matching_direction(source_event_id: str, direction: DirectionEstimate) -> None:
    if direction.source_event_id != source_event_id:
        raise ValueError("direction estimate belongs to a different source event")
