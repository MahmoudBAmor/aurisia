"""In-memory client adapter for a persistent local whisper.cpp process."""

from __future__ import annotations

import hashlib
import http.client
import io
import json
import secrets
import time
import wave
from collections.abc import Callable
from pathlib import Path
from typing import Any

from aurisia.contracts import ModelDescriptor, SpeechSegment

from ..measurements import SpeechInferenceMeasurement
from ..ports import SpeechHypothesis

InferenceRequest = Callable[[str, bytes, str, float], bytes]


class WhisperServiceUnavailable(RuntimeError):
    """Raised when the local whisper.cpp process cannot serve inference."""


class WhisperCppSpeechEngine:
    """Transcribe canonical segments through the persistent loopback runtime."""

    def __init__(
        self,
        *,
        endpoint: str,
        model: ModelDescriptor,
        language: str,
        supported_locale: str,
        sample_rate_hz: int,
        channels: int,
        timeout_seconds: float,
        request_inference: InferenceRequest | None = None,
        measurement_sink: Callable[[SpeechInferenceMeasurement], None] | None = None,
    ) -> None:
        if sample_rate_hz <= 0:
            raise ValueError("Whisper sample rate must be positive")
        if channels != 1:
            raise ValueError("Whisper currently requires canonical mono audio")
        if timeout_seconds <= 0:
            raise ValueError("Whisper timeout must be positive")
        if not language:
            raise ValueError("Whisper language must not be empty")
        if not supported_locale:
            raise ValueError("supported locale must not be empty")
        _split_endpoint(endpoint)

        self._endpoint = endpoint
        self._model = model
        self._language = language
        self._supported_locale = supported_locale
        self._sample_rate_hz = sample_rate_hz
        self._channels = channels
        self._timeout_seconds = timeout_seconds
        self._request_inference = request_inference or _request_inference
        self._measurement_sink = measurement_sink

    @property
    def model(self) -> ModelDescriptor:
        return self._model

    def transcribe(self, segment: SpeechSegment, locale: str) -> SpeechHypothesis:
        if locale != self._supported_locale:
            raise ValueError(
                f"Whisper adapter supports {self._supported_locale}, got {locale}"
            )
        if (segment.sample_rate_hz, segment.channels) != (
            self._sample_rate_hz,
            self._channels,
        ):
            raise ValueError(
                "speech segment does not match the Whisper audio contract: "
                f"expected {self._sample_rate_hz} Hz/{self._channels}ch, "
                f"got {segment.sample_rate_hz} Hz/{segment.channels}ch"
            )

        body, content_type = _multipart_request(
            _wave_bytes(segment),
            language=self._language,
        )
        started_ns = time.perf_counter_ns()
        response = self._request_inference(
            self._endpoint,
            body,
            content_type,
            self._timeout_seconds,
        )
        elapsed_ms = (time.perf_counter_ns() - started_ns) / 1_000_000
        if self._measurement_sink is not None:
            self._measurement_sink(
                SpeechInferenceMeasurement(
                    audio_duration_ms=segment.end_time_ms - segment.start_time_ms,
                    inference_latency_ms=elapsed_ms,
                )
            )
        return SpeechHypothesis(text=_parse_transcript(response), confidence=None)


def wait_for_whisper_service(endpoint: str, *, timeout_seconds: float) -> None:
    """Wait until the pinned local server reports that its model is ready."""

    if timeout_seconds <= 0:
        raise ValueError("Whisper health timeout must be positive")
    host, port = _split_endpoint(endpoint)
    deadline = time.monotonic() + timeout_seconds
    last_error: OSError | http.client.HTTPException | None = None
    while time.monotonic() < deadline:
        connection = http.client.HTTPConnection(
            host,
            port,
            timeout=min(0.25, max(0.01, deadline - time.monotonic())),
        )
        try:
            connection.request("GET", "/health")
            response = connection.getresponse()
            payload = response.read()
            if response.status == 200 and _health_is_ready(payload):
                return
        except (OSError, http.client.HTTPException) as exc:
            last_error = exc
        finally:
            connection.close()
        time.sleep(0.05)
    raise WhisperServiceUnavailable(
        f"whisper.cpp service at {endpoint} did not become ready"
    ) from last_error


def verify_whisper_runtime(path: Path, expected_sha256: str) -> None:
    if not path.is_file():
        raise WhisperServiceUnavailable(
            f"whisper.cpp runtime is missing: {path}. "
            "Run tools/install-whisper.ps1 from PowerShell."
        )
    expected = expected_sha256.lower()
    if len(expected) != 64 or any(character not in "0123456789abcdef" for character in expected):
        raise ValueError("whisper.cpp executable checksum must be a SHA-256 digest")
    digest = hashlib.sha256()
    try:
        with path.open("rb") as executable:
            for chunk in iter(lambda: executable.read(1024 * 1024), b""):
                digest.update(chunk)
    except OSError as exc:
        raise WhisperServiceUnavailable(
            f"cannot verify whisper.cpp runtime: {exc}"
        ) from exc
    if digest.hexdigest() != expected:
        raise WhisperServiceUnavailable(
            "whisper.cpp runtime checksum mismatch; rerun tools/install-whisper.ps1"
        )


def _request_inference(
    endpoint: str,
    body: bytes,
    content_type: str,
    timeout_seconds: float,
) -> bytes:
    host, port = _split_endpoint(endpoint)
    connection = http.client.HTTPConnection(host, port, timeout=timeout_seconds)
    try:
        connection.request(
            "POST",
            "/inference",
            body=body,
            headers={
                "Content-Type": content_type,
                "Content-Length": str(len(body)),
                "Connection": "close",
            },
        )
        response = connection.getresponse()
        payload = response.read()
    except (OSError, http.client.HTTPException) as exc:
        raise WhisperServiceUnavailable(
            f"whisper.cpp inference request failed: {exc}"
        ) from exc
    finally:
        connection.close()
    if response.status != 200:
        detail = payload.decode("utf-8", errors="replace").strip()
        raise WhisperServiceUnavailable(
            f"whisper.cpp inference failed with HTTP {response.status}: {detail[:500]}"
        )
    return payload


def _wave_bytes(segment: SpeechSegment) -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as audio:
        audio.setnchannels(segment.channels)
        audio.setsampwidth(2)
        audio.setframerate(segment.sample_rate_hz)
        audio.writeframes(segment.pcm_s16le)
    return buffer.getvalue()


def _multipart_request(audio: bytes, *, language: str) -> tuple[bytes, str]:
    boundary = f"aurisia-{secrets.token_hex(16)}"
    chunks: list[bytes] = []

    def field(name: str, value: str) -> None:
        chunks.extend(
            (
                f"--{boundary}\r\n".encode(),
                f'Content-Disposition: form-data; name="{name}"\r\n\r\n'.encode(),
                value.encode("utf-8"),
                b"\r\n",
            )
        )

    chunks.extend(
        (
            f"--{boundary}\r\n".encode(),
            b'Content-Disposition: form-data; name="file"; filename="speech.wav"\r\n',
            b"Content-Type: audio/wav\r\n\r\n",
            audio,
            b"\r\n",
        )
    )
    field("response_format", "json")
    field("language", language)
    field("translate", "false")
    field("no_timestamps", "true")
    field("suppress_nst", "true")
    chunks.append(f"--{boundary}--\r\n".encode())
    return b"".join(chunks), f"multipart/form-data; boundary={boundary}"


def _parse_transcript(response: bytes) -> str:
    try:
        payload: Any = json.loads(response.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise WhisperServiceUnavailable("whisper.cpp returned invalid JSON") from exc
    if not isinstance(payload, dict):
        raise WhisperServiceUnavailable("whisper.cpp response does not contain text")
    text = payload.get("text")
    if not isinstance(text, str):
        raise WhisperServiceUnavailable("whisper.cpp response does not contain text")
    return text.strip()


def _health_is_ready(payload: bytes) -> bool:
    try:
        value: Any = json.loads(payload.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError):
        return False
    return isinstance(value, dict) and value.get("status") == "ok"


def _split_endpoint(endpoint: str) -> tuple[str, int]:
    try:
        host, port_text = endpoint.rsplit(":", maxsplit=1)
        port = int(port_text)
    except ValueError as exc:
        raise ValueError("Whisper endpoint must use host:port syntax") from exc
    normalized_host = host.strip("[]")
    if normalized_host not in {"127.0.0.1", "localhost", "::1"}:
        raise ValueError("Whisper endpoint must use a loopback host")
    if not 1 <= port <= 65_535:
        raise ValueError("Whisper endpoint port must be in [1, 65535]")
    return normalized_host, port
