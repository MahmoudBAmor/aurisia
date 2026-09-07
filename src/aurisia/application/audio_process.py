"""Lifecycle supervision for the local audio service process."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from types import TracebackType

from aurisia.config import AppConfig
from aurisia.services.audio.adapters import (
    AudioServiceUnavailable,
    wait_for_audio_service,
)


class AudioServiceProcess:
    """Start, health-check, and stop one local audio service process."""

    def __init__(self, config: AppConfig, config_path: Path) -> None:
        self._config = config
        self._config_path = config_path
        self._process: subprocess.Popen[bytes] | None = None

    def start(self) -> None:
        if self._process is not None:
            raise RuntimeError("audio service process is already started")
        try:
            wait_for_audio_service(
                self._config.audio.grpc_endpoint,
                timeout_seconds=0.25,
            )
        except AudioServiceUnavailable:
            pass
        else:
            raise AudioServiceUnavailable(
                f"audio service endpoint {self._config.audio.grpc_endpoint} is already in use"
            )
        self._process = subprocess.Popen(
            [
                sys.executable,
                "-m",
                "aurisia.services.audio.grpc_server",
                "--config",
                str(self._config_path),
            ],
            stdin=subprocess.DEVNULL,
        )
        try:
            wait_for_audio_service(
                self._config.audio.grpc_endpoint,
                timeout_seconds=8.0,
            )
            exit_code = self._process.poll()
            if exit_code is not None:
                raise AudioServiceUnavailable(
                    f"audio service exited during startup with code {exit_code}"
                )
        except AudioServiceUnavailable:
            exit_code = self._process.poll()
            self.stop()
            if exit_code is not None:
                raise AudioServiceUnavailable(
                    f"audio service exited during startup with code {exit_code}"
                ) from None
            raise

    def stop(self) -> None:
        process = self._process
        self._process = None
        if process is None or process.poll() is not None:
            return
        process.terminate()
        try:
            process.wait(timeout=3.0)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait(timeout=2.0)

    def __enter__(self) -> AudioServiceProcess:
        self.start()
        return self

    def __exit__(
        self,
        exc_type: type[BaseException] | None,
        exc_value: BaseException | None,
        traceback: TracebackType | None,
    ) -> None:
        del exc_type, exc_value, traceback
        self.stop()
