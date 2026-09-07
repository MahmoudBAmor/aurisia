from __future__ import annotations

import unittest
from dataclasses import replace
from pathlib import Path
from unittest.mock import Mock, patch

from aurisia.application.speech_process import WhisperServerProcess
from aurisia.config import AppConfig, load_config
from aurisia.services.speech.adapters import WhisperServiceUnavailable


class WhisperServerProcessTests(unittest.TestCase):
    def test_start_refuses_an_endpoint_already_serving_whisper(self) -> None:
        supervisor = WhisperServerProcess(_whisper_config())

        with (
            patch(
                "aurisia.application.speech_process.wait_for_whisper_service",
            ) as wait_for_service,
            patch("aurisia.application.speech_process.subprocess.Popen") as popen,
            self.assertRaisesRegex(WhisperServiceUnavailable, "already in use"),
        ):
            supervisor.start()

        wait_for_service.assert_called_once()
        popen.assert_not_called()

    def test_start_uses_verified_model_and_loopback_configuration(self) -> None:
        config = _whisper_config()
        supervisor = WhisperServerProcess(config)
        process = Mock()
        process.poll.return_value = None
        pack = Mock()
        pack.artifact.return_value.path = Path("models/test/model.bin")

        with (
            patch(
                "aurisia.application.speech_process.wait_for_whisper_service",
                side_effect=[WhisperServiceUnavailable("not ready"), None],
            ),
            patch(
                "aurisia.application.speech_process.verify_whisper_runtime",
            ) as verify_runtime,
            patch(
                "aurisia.application.speech_process.load_verified_model_pack",
                return_value=pack,
            ),
            patch(
                "aurisia.application.speech_process.subprocess.Popen",
                return_value=process,
            ) as popen,
        ):
            supervisor.start()
            supervisor.stop()

        verify_runtime.assert_called_once_with(
            config.speech.executable_path,
            config.speech.executable_sha256,
        )
        command = popen.call_args.args[0]
        self.assertEqual(command[0], str(config.speech.executable_path))
        self.assertEqual(command[command.index("--host") + 1], "127.0.0.1")
        self.assertEqual(command[command.index("--port") + 1], "50052")
        self.assertEqual(command[command.index("--threads") + 1], "4")
        self.assertIn("--no-gpu", command)
        self.assertIn("--suppress-nst", command)
        process.terminate.assert_called_once()


def _whisper_config() -> AppConfig:
    config = load_config(Path("config/aurisia.yaml"))
    return replace(
        config,
        models=replace(config.models, speech_adapter="whisper_cpp"),
        speech=replace(
            config.speech,
            model_manifest_path=Path(
                "models/whisper-small-q5_1/manifest.yaml"
            ).resolve(),
        ),
    )


if __name__ == "__main__":
    unittest.main()
