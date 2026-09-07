from __future__ import annotations

import unittest

from aurisia.contracts import AudioFrame, ModelDescriptor


class ContractTests(unittest.TestCase):
    def test_audio_frame_derives_duration_from_format(self) -> None:
        frame = AudioFrame(
            stream_id="test",
            sequence=0,
            captured_at_ms=40,
            sample_rate_hz=16_000,
            channels=1,
            pcm_s16le=b"\x00\x00" * 320,
        )

        self.assertEqual(frame.samples_per_channel, 320)
        self.assertEqual(frame.duration_ms, 20)
        self.assertEqual(frame.end_time_ms, 60)

    def test_audio_frame_rejects_incomplete_samples(self) -> None:
        with self.assertRaisesRegex(ValueError, "complete interleaved"):
            AudioFrame(
                stream_id="test",
                sequence=0,
                captured_at_ms=0,
                sample_rate_hz=16_000,
                channels=2,
                pcm_s16le=b"\x00\x00",
            )

    def test_model_descriptor_requires_explicit_runtime(self) -> None:
        with self.assertRaisesRegex(ValueError, "runtime"):
            ModelDescriptor(model_id="model", version="1", runtime="")


if __name__ == "__main__":
    unittest.main()
