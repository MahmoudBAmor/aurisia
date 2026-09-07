from __future__ import annotations

import unittest
from pathlib import Path
from unittest.mock import patch

from aurisia.application.audio_process import AudioServiceProcess
from aurisia.config import load_config
from aurisia.services.audio.adapters import AudioServiceUnavailable


class AudioServiceProcessTests(unittest.TestCase):
    def test_start_refuses_an_endpoint_already_serving_aurisia(self) -> None:
        config_path = Path("config/aurisia.yaml")
        supervisor = AudioServiceProcess(load_config(config_path), config_path)

        with (
            patch(
                "aurisia.application.audio_process.wait_for_audio_service",
            ) as wait_for_service,
            patch("aurisia.application.audio_process.subprocess.Popen") as popen,
            self.assertRaisesRegex(AudioServiceUnavailable, "already in use"),
        ):
            supervisor.start()

        wait_for_service.assert_called_once()
        popen.assert_not_called()


if __name__ == "__main__":
    unittest.main()
