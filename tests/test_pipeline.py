from __future__ import annotations

import unittest
from dataclasses import replace
from pathlib import Path

from aurisia.application.demo import build_demo_pipeline
from aurisia.application.live import build_live_pipeline
from aurisia.config import load_config
from aurisia.contracts import PerceptionKind, Priority
from aurisia.services.audio.adapters import SyntheticAudioSource


class PipelineTests(unittest.TestCase):
    def test_deterministic_pipeline_produces_arabic_perception_events(self) -> None:
        config = load_config(Path("config/aurisia.yaml"))

        events = tuple(build_demo_pipeline(config).run())

        self.assertEqual(len(events), 2)
        speech, doorbell = events
        self.assertEqual(speech.kind, PerceptionKind.SPEECH)
        self.assertEqual(speech.title, "نحب نعمل رونديفو غدوة على 10")
        self.assertEqual(speech.priority, Priority.CONVERSATION)
        self.assertEqual(doorbell.kind, PerceptionKind.SOUND)
        self.assertEqual(doorbell.title, "جرس الباب")
        self.assertEqual(doorbell.icon, "🔔")
        self.assertEqual(doorbell.priority, Priority.ATTENTION)

    def test_direction_simulation_is_repeatable(self) -> None:
        config = load_config(Path("config/aurisia.yaml"))

        first = tuple(build_demo_pipeline(config).run())
        second = tuple(build_demo_pipeline(config).run())

        self.assertEqual(
            [event.direction for event in first],
            [event.direction for event in second],
        )

    def test_live_calibration_detects_reference_pc_voice_but_not_room_level(self) -> None:
        config = load_config(Path("config/aurisia.yaml"))
        config = replace(
            config,
            models=replace(
                config.models,
                vad_adapter="energy_vad",
                speech_adapter="scripted_aeb_tn",
            ),
        )
        room_level = SyntheticAudioSource([78] * 20)
        voice_then_silence = SyntheticAudioSource([78] * 5 + [320] * 10 + [78] * 5)

        room_events = tuple(build_live_pipeline(config, room_level).run())
        voice_events = tuple(build_live_pipeline(config, voice_then_silence).run())

        self.assertEqual(room_events, ())
        self.assertEqual(len(voice_events), 1)
        self.assertEqual(voice_events[0].kind, PerceptionKind.SPEECH)

    def test_live_segmentation_keeps_audio_before_vad_start(self) -> None:
        config = load_config(Path("config/aurisia.yaml"))
        config = replace(
            config,
            models=replace(
                config.models,
                vad_adapter="energy_vad",
                speech_adapter="scripted_aeb_tn",
            ),
            vad=replace(config.vad, end_silence_frames=2),
            speech=replace(
                config.speech,
                minimum_segment_ms=100,
                pre_roll_ms=60,
            ),
        )
        source = SyntheticAudioSource([0] * 10 + [4_500] * 5 + [0] * 3)

        events = tuple(build_live_pipeline(config, source).run())

        self.assertEqual(len(events), 1)
        self.assertEqual(events[0].start_time_ms, 140)

    def test_continuous_speech_is_bounded_and_published_without_vad_end(self) -> None:
        config = load_config(Path("config/aurisia.yaml"))
        config = replace(
            config,
            models=replace(
                config.models,
                vad_adapter="energy_vad",
                speech_adapter="scripted_aeb_tn",
            ),
            speech=replace(
                config.speech,
                minimum_segment_ms=40,
                pre_roll_ms=0,
                partial_interval_ms=20,
                maximum_segment_ms=100,
            ),
        )
        source = SyntheticAudioSource([4_500] * 15)

        events = tuple(build_live_pipeline(config, source).run())

        self.assertEqual(len(events), 3)
        self.assertEqual(
            [(event.start_time_ms, event.end_time_ms) for event in events],
            [(0, 100), (100, 200), (200, 300)],
        )


if __name__ == "__main__":
    unittest.main()
