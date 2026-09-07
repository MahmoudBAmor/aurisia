from __future__ import annotations

import struct
import unittest
from collections.abc import Iterator

from aurisia.contracts import AudioFrame
from aurisia.services.audio.adapters import NormalizingAudioSource


class _StereoSource:
    def __init__(self, frame_count: int = 5) -> None:
        self._frame_count = frame_count

    def frames(self) -> Iterator[AudioFrame]:
        sample_rate_hz = 48_000
        samples_per_frame = sample_rate_hz * 20 // 1_000
        for sequence in range(self._frame_count):
            interleaved = [value for _ in range(samples_per_frame) for value in (2_000, 0)]
            yield AudioFrame(
                stream_id="stereo",
                sequence=sequence,
                captured_at_ms=sequence * 20,
                sample_rate_hz=sample_rate_hz,
                channels=2,
                pcm_s16le=struct.pack(f"<{len(interleaved)}h", *interleaved),
            )


class AudioNormalizationTests(unittest.TestCase):
    def test_resamples_stereo_48khz_to_fixed_16khz_mono_frames(self) -> None:
        frames = tuple(NormalizingAudioSource(_StereoSource()).frames())

        self.assertEqual(len(frames), 5)
        self.assertTrue(all(frame.sample_rate_hz == 16_000 for frame in frames))
        self.assertTrue(all(frame.channels == 1 for frame in frames))
        self.assertTrue(all(frame.samples_per_channel == 320 for frame in frames))
        self.assertEqual([frame.sequence for frame in frames], list(range(5)))
        self.assertEqual([frame.captured_at_ms for frame in frames], [0, 20, 40, 60, 80])

    def test_downmixes_channels_before_model_inference(self) -> None:
        frames = tuple(NormalizingAudioSource(_StereoSource(frame_count=1)).frames())
        samples = struct.unpack("<320h", frames[0].pcm_s16le)

        self.assertAlmostEqual(sum(samples) / len(samples), 1_000, delta=50)

    def test_flush_handles_multiple_delayed_resampler_frames(self) -> None:
        frames = tuple(
            NormalizingAudioSource(
                _StereoSource(frame_count=100),
                quality="VHQ",
            ).frames()
        )

        self.assertEqual(len(frames), 100)
        self.assertTrue(all(frame.samples_per_channel == 320 for frame in frames))


if __name__ == "__main__":
    unittest.main()
