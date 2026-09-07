from __future__ import annotations

import struct
import tempfile
import unittest
import wave
from pathlib import Path

from aurisia.services.audio.adapters import WaveFileAudioSource


class WaveFileAudioSourceTests(unittest.TestCase):
    def test_pcm_wave_is_split_into_timestamped_frames(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "fixture.wav"
            with wave.open(str(path), "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(16_000)
                wav.writeframes(struct.pack("<640h", *([100] * 640)))

            frames = tuple(WaveFileAudioSource(path).frames())

        self.assertEqual(len(frames), 2)
        self.assertEqual(frames[0].sequence, 0)
        self.assertEqual(frames[1].sequence, 1)
        self.assertEqual(frames[1].captured_at_ms, 20)
        self.assertEqual(frames[0].duration_ms, 20)


if __name__ == "__main__":
    unittest.main()
