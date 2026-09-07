"""Windows-first PortAudio microphone adapter using python-sounddevice."""

from __future__ import annotations

import queue
import threading
from collections.abc import Iterator, Sequence
from contextlib import suppress
from dataclasses import dataclass
from typing import Any

from aurisia.contracts import AudioDevice, AudioFrame, AudioMetrics


@dataclass(frozen=True, slots=True)
class _CapturedBlock:
    sequence: int
    pcm: bytes


class AudioBackendUnavailable(RuntimeError):
    """Raised when the optional microphone backend is not installed."""


class AudioDeviceSelectionError(ValueError):
    """Raised when a configured microphone cannot be selected unambiguously."""


class SoundDeviceAudioSource:
    """Capture fixed-duration signed 16-bit PCM frames without blocking callbacks."""

    def __init__(
        self,
        *,
        device: str = "default",
        sample_rate_hz: int = 16_000,
        channels: int = 1,
        frame_duration_ms: int = 20,
        queue_capacity: int = 256,
        reconnect_delay_ms: int = 1_000,
        stream_id: str = "microphone",
    ) -> None:
        if sample_rate_hz <= 0:
            raise ValueError("sample_rate_hz must be positive")
        if channels <= 0:
            raise ValueError("channels must be positive")
        if frame_duration_ms <= 0:
            raise ValueError("frame_duration_ms must be positive")
        if queue_capacity <= 0:
            raise ValueError("queue_capacity must be positive")
        if reconnect_delay_ms <= 0:
            raise ValueError("reconnect_delay_ms must be positive")
        frames_per_block = sample_rate_hz * frame_duration_ms // 1000
        if frames_per_block <= 0:
            raise ValueError("frame duration is too short for the selected sample rate")

        self._device_selector = device
        self._sample_rate_hz = sample_rate_hz
        self._channels = channels
        self._frame_duration_ms = frame_duration_ms
        self._frames_per_block = frames_per_block
        self._queue: queue.Queue[_CapturedBlock] = queue.Queue(maxsize=queue_capacity)
        self._reconnect_delay_seconds = reconnect_delay_ms / 1000
        self._stream_id = stream_id
        self._stop = threading.Event()
        self._metrics_lock = threading.Lock()
        self._frames_captured = 0
        self._frames_dropped = 0
        self._callback_warnings = 0
        self._reconnect_attempts = 0
        self._last_error: str | None = None

    def frames(self) -> Iterator[AudioFrame]:
        sounddevice = _load_sounddevice()
        devices = list_input_devices()
        resolved_device = resolve_device_selector(devices, self._device_selector)
        try:
            sounddevice.check_input_settings(
                device=resolved_device,
                channels=self._channels,
                dtype="int16",
                samplerate=self._sample_rate_hz,
            )
        except sounddevice.PortAudioError as exc:
            raise AudioDeviceSelectionError(
                f"microphone does not support {self._sample_rate_hz} Hz/"
                f"{self._channels} channel PCM: {exc}"
            ) from exc
        expected_bytes = self._frames_per_block * self._channels * 2
        self._stop.clear()

        def callback(
            indata: Any,
            frame_count: int,
            time_info: Any,
            status: Any,
        ) -> None:
            del time_info
            if status:
                self._increment_metric("callback_warnings")
                self._set_last_error(str(status))
            sequence = self._record_capture()
            pcm = bytes(indata)
            if frame_count != self._frames_per_block or len(pcm) != expected_bytes:
                self._increment_metric("callback_warnings")
                self._set_last_error(
                    f"unexpected callback block: {frame_count} frames, {len(pcm)} bytes"
                )
                return
            self._enqueue_latest(_CapturedBlock(sequence, pcm))

        while not self._stop.is_set():
            try:
                with sounddevice.RawInputStream(
                    samplerate=self._sample_rate_hz,
                    blocksize=self._frames_per_block,
                    device=resolved_device,
                    channels=self._channels,
                    dtype="int16",
                    callback=callback,
                ) as stream:
                    self._set_last_error(None)
                    while stream.active and not self._stop.is_set():
                        try:
                            block = self._queue.get(timeout=0.25)
                        except queue.Empty:
                            continue
                        yield AudioFrame(
                            stream_id=self._stream_id,
                            sequence=block.sequence,
                            captured_at_ms=block.sequence * self._frame_duration_ms,
                            sample_rate_hz=self._sample_rate_hz,
                            channels=self._channels,
                            pcm_s16le=block.pcm,
                        )
            except sounddevice.PortAudioError as exc:
                self._increment_metric("reconnect_attempts")
                self._set_last_error(str(exc))
                if self._stop.wait(self._reconnect_delay_seconds):
                    break

    def close(self) -> None:
        self._stop.set()

    def metrics(self) -> AudioMetrics:
        with self._metrics_lock:
            return AudioMetrics(
                frames_captured=self._frames_captured,
                frames_dropped=self._frames_dropped,
                callback_warnings=self._callback_warnings,
                reconnect_attempts=self._reconnect_attempts,
                last_error=self._last_error,
            )

    def _enqueue_latest(self, block: _CapturedBlock) -> None:
        try:
            self._queue.put_nowait(block)
            return
        except queue.Full:
            pass
        with suppress(queue.Empty):
            self._queue.get_nowait()
        self._increment_metric("frames_dropped")
        try:
            self._queue.put_nowait(block)
        except queue.Full:
            self._increment_metric("frames_dropped")

    def _record_capture(self) -> int:
        with self._metrics_lock:
            sequence = self._frames_captured
            self._frames_captured += 1
            return sequence

    def _increment_metric(self, name: str) -> None:
        with self._metrics_lock:
            if name == "frames_dropped":
                self._frames_dropped += 1
            elif name == "callback_warnings":
                self._callback_warnings += 1
            elif name == "reconnect_attempts":
                self._reconnect_attempts += 1
            else:  # pragma: no cover - all callers use constants above
                raise ValueError(f"unknown audio metric {name}")

    def _set_last_error(self, value: str | None) -> None:
        with self._metrics_lock:
            self._last_error = value


def list_input_devices() -> tuple[AudioDevice, ...]:
    sounddevice = _load_sounddevice()
    raw_devices = sounddevice.query_devices()
    host_apis = sounddevice.query_hostapis()
    default_device = sounddevice.default.device
    default_input = int(default_device[0]) if default_device else -1
    devices: list[AudioDevice] = []
    for index, raw in enumerate(raw_devices):
        max_input_channels = int(raw["max_input_channels"])
        if max_input_channels <= 0:
            continue
        host_api_index = int(raw["hostapi"])
        host_api_name = str(host_apis[host_api_index]["name"])
        devices.append(
            AudioDevice(
                id=str(index),
                name=str(raw["name"]),
                host_api=host_api_name,
                max_input_channels=max_input_channels,
                default_sample_rate_hz=float(raw["default_samplerate"]),
                is_default=index == default_input,
            )
        )
    return tuple(devices)


def resolve_device_selector(
    devices: Sequence[AudioDevice],
    selector: str,
) -> int | None:
    normalized = selector.strip()
    if not normalized or normalized.casefold() == "default":
        return None
    if normalized.isdecimal():
        selected_id = str(int(normalized))
        if any(device.id == selected_id for device in devices):
            return int(selected_id)
        raise AudioDeviceSelectionError(f"input device id {selected_id} was not found")

    exact = [device for device in devices if device.name.casefold() == normalized.casefold()]
    if len(exact) == 1:
        return int(exact[0].id)
    matches = [device for device in devices if normalized.casefold() in device.name.casefold()]
    if not matches:
        raise AudioDeviceSelectionError(f"no input device matches {selector!r}")
    if len(matches) > 1:
        names = ", ".join(f"{device.id}: {device.name}" for device in matches)
        raise AudioDeviceSelectionError(f"input device selector {selector!r} is ambiguous: {names}")
    return int(matches[0].id)


def _load_sounddevice() -> Any:
    try:
        import sounddevice  # type: ignore[import-untyped]
    except ImportError as exc:
        raise AudioBackendUnavailable(
            "sounddevice is not installed; install Aurisia's 'audio' extra"
        ) from exc
    return sounddevice
