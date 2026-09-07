from __future__ import annotations

import struct
import unittest
from collections.abc import Callable, Generator
from pathlib import Path
from types import SimpleNamespace
from typing import Any, cast
from unittest.mock import patch

from aurisia.config import load_config
from aurisia.contracts import AudioDevice, AudioFrame
from aurisia.services.audio.adapters import (
    AudioDeviceSelectionError,
    GrpcAudioSource,
    SoundDeviceAudioSource,
    SyntheticAudioSource,
    list_remote_input_devices,
    resolve_device_selector,
    sounddevice_source,
    wait_for_audio_service,
)
from aurisia.services.audio.buffer import CircularAudioBuffer
from aurisia.services.audio.grpc_server import create_server


class AudioBufferTests(unittest.TestCase):
    def test_circular_buffer_retains_only_the_latest_frames(self) -> None:
        frames = tuple(SyntheticAudioSource([100, 200, 300]).frames())
        buffer = CircularAudioBuffer(capacity_frames=2)

        for frame in frames:
            buffer.append(frame)

        self.assertEqual([frame.sequence for frame in buffer.snapshot()], [1, 2])


class AudioDeviceSelectionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.devices = (
            AudioDevice("2", "Microphone Array", "WASAPI", 2, 48_000.0, True),
            AudioDevice("4", "USB Conference Mic", "WASAPI", 1, 48_000.0, False),
        )

    def test_default_device_uses_backend_default(self) -> None:
        self.assertIsNone(resolve_device_selector(self.devices, "default"))

    def test_device_can_be_selected_by_id_or_unique_name_fragment(self) -> None:
        self.assertEqual(resolve_device_selector(self.devices, "4"), 4)
        self.assertEqual(resolve_device_selector(self.devices, "conference"), 4)

    def test_ambiguous_or_missing_device_is_rejected(self) -> None:
        with self.assertRaises(AudioDeviceSelectionError):
            resolve_device_selector(self.devices, "mic")
        with self.assertRaises(AudioDeviceSelectionError):
            resolve_device_selector(self.devices, "missing")


class _BurstingInputStream:
    active = True

    def __init__(self, callback: Callable[..., None], blocksize: int) -> None:
        self._callback = callback
        self._blocksize = blocksize

    def __enter__(self) -> _BurstingInputStream:
        pcm = struct.pack("<h", 1_000) * self._blocksize
        for _ in range(3):
            self._callback(pcm, self._blocksize, None, None)
        return self

    def __exit__(self, *args: object) -> None:
        del args


class _BurstingSoundDevice:
    PortAudioError = RuntimeError
    default = SimpleNamespace(device=(0, 0))

    def query_devices(self) -> list[dict[str, object]]:
        return [
            {
                "name": "Test Microphone",
                "hostapi": 0,
                "max_input_channels": 1,
                "default_samplerate": 16_000.0,
            }
        ]

    def query_hostapis(self) -> list[dict[str, object]]:
        return [{"name": "Test API"}]

    def check_input_settings(self, **settings: object) -> None:
        del settings

    def RawInputStream(self, **settings: Any) -> _BurstingInputStream:
        return _BurstingInputStream(settings["callback"], settings["blocksize"])


class SoundDeviceAudioSourceTests(unittest.TestCase):
    def test_overload_drops_oldest_frame_and_preserves_sequence_gap(self) -> None:
        source = SoundDeviceAudioSource(queue_capacity=1)

        with patch.object(
            sounddevice_source,
            "_load_sounddevice",
            return_value=_BurstingSoundDevice(),
        ):
            frames = cast(Generator[AudioFrame, None, None], source.frames())
            try:
                frame = next(frames)
            finally:
                source.close()
                frames.close()

        self.assertEqual(frame.sequence, 2)
        self.assertEqual(source.metrics().frames_captured, 3)
        self.assertEqual(source.metrics().frames_dropped, 2)


class AudioGrpcTransportTests(unittest.TestCase):
    def test_audio_frames_and_device_metadata_cross_grpc_boundary(self) -> None:
        config = load_config(Path("config/aurisia.yaml"))
        expected_device = AudioDevice(
            "7",
            "Test Microphone",
            "Test API",
            1,
            16_000.0,
            True,
        )
        server, port = create_server(
            config,
            endpoint="127.0.0.1:0",
            source_factory=lambda request: SyntheticAudioSource(
                [500, 1_000, 1_500],
                stream_id=f"grpc:{request.device_id}",
            ),
            device_provider=lambda: (expected_device,),
        )
        endpoint = f"127.0.0.1:{port}"
        server.start()
        try:
            wait_for_audio_service(endpoint)
            devices = list_remote_input_devices(endpoint)
            source = GrpcAudioSource(
                endpoint,
                device="7",
                sample_rate_hz=16_000,
                channels=1,
                frame_duration_ms=20,
                queue_capacity=8,
            )
            frames = tuple(source.frames())
        finally:
            server.stop(grace=0).wait()

        self.assertEqual(devices, (expected_device,))
        self.assertEqual(len(frames), 3)
        self.assertEqual(frames[0].stream_id, "grpc:7")
        self.assertEqual([frame.sequence for frame in frames], [0, 1, 2])


if __name__ == "__main__":
    unittest.main()
