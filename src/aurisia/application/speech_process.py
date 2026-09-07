"""Lifecycle supervision for the local persistent whisper.cpp process."""

from __future__ import annotations

import subprocess
import time
from types import TracebackType

from aurisia.config import AppConfig
from aurisia.model_packs import load_verified_model_pack
from aurisia.services.speech.adapters import (
    WhisperServiceUnavailable,
    verify_whisper_runtime,
    wait_for_whisper_service,
)


class WhisperServerProcess:
    """Start, health-check, and stop one pinned loopback ASR process."""

    def __init__(self, config: AppConfig) -> None:
        self._config = config
        self._process: subprocess.Popen[bytes] | None = None

    def start(self) -> None:
        if self._process is not None:
            raise RuntimeError("whisper.cpp service process is already started")
        if self._config.models.speech_adapter != "whisper_cpp":
            raise RuntimeError("whisper.cpp process requires the whisper_cpp speech adapter")

        try:
            wait_for_whisper_service(
                self._config.speech.endpoint,
                timeout_seconds=0.2,
            )
        except WhisperServiceUnavailable:
            pass
        else:
            raise WhisperServiceUnavailable(
                f"speech endpoint {self._config.speech.endpoint} is already in use"
            )

        verify_whisper_runtime(
            self._config.speech.executable_path,
            self._config.speech.executable_sha256,
        )
        pack = load_verified_model_pack(self._config.speech.model_manifest_path)
        model_path = pack.artifact("whisper_model").path
        host, port = self._config.speech.endpoint.rsplit(":", maxsplit=1)
        self._process = subprocess.Popen(
            [
                str(self._config.speech.executable_path),
                "--model",
                str(model_path),
                "--host",
                host.strip("[]"),
                "--port",
                port,
                "--threads",
                str(self._config.speech.threads),
                "--language",
                self._config.speech.language,
                "--no-gpu",
                "--no-timestamps",
                "--suppress-nst",
                "--no-language-probabilities",
            ],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0),
        )
        try:
            self._wait_until_ready()
        except WhisperServiceUnavailable:
            exit_code = self._process.poll()
            self.stop()
            if exit_code is not None:
                raise WhisperServiceUnavailable(
                    f"whisper.cpp service exited during startup with code {exit_code}"
                ) from None
            raise

    def _wait_until_ready(self) -> None:
        process = self._process
        if process is None:
            raise RuntimeError("whisper.cpp service process has not been started")
        deadline = time.monotonic() + self._config.speech.startup_timeout_seconds
        while time.monotonic() < deadline:
            exit_code = process.poll()
            if exit_code is not None:
                raise WhisperServiceUnavailable(
                    f"whisper.cpp service exited during startup with code {exit_code}"
                )
            try:
                wait_for_whisper_service(
                    self._config.speech.endpoint,
                    timeout_seconds=min(0.25, max(0.01, deadline - time.monotonic())),
                )
            except WhisperServiceUnavailable:
                continue
            return
        raise WhisperServiceUnavailable(
            f"whisper.cpp service at {self._config.speech.endpoint} "
            "did not become ready before the startup timeout"
        )

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

    def __enter__(self) -> WhisperServerProcess:
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
