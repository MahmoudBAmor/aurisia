from __future__ import annotations

import math
import unittest

from aurisia.services.audio.adapters import SyntheticAudioSource
from aurisia.services.audio.levels import rms_dbfs


class AudioLevelTests(unittest.TestCase):
    def test_silence_is_negative_infinity(self) -> None:
        frame = next(iter(SyntheticAudioSource([0]).frames()))

        self.assertEqual(rms_dbfs(frame), -math.inf)

    def test_full_scale_constant_is_zero_dbfs(self) -> None:
        frame = next(iter(SyntheticAudioSource([32_767]).frames()))

        self.assertAlmostEqual(rms_dbfs(frame), 0.0, places=2)


if __name__ == "__main__":
    unittest.main()
