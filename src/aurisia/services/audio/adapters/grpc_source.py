"""gRPC client adapter exposing the remote audio process as an AudioSource."""

from __future__ import annotations

import threading
from collections.abc import Iterator
from typing import Any

import grpc

from aurisia.contracts import AudioDevice, AudioFrame
from aurisia.v1 import aurisia_pb2, aurisia_pb2_grpc


class AudioServiceUnavailable(RuntimeError):
    """Raised when the local audio process cannot serve a request."""


class GrpcAudioSource:
    """Read ordered PCM frames from the loopback audio capture service."""

    def __init__(
        self,
        endpoint: str,
        *,
        device: str,
        sample_rate_hz: int,
        channels: int,
        frame_duration_ms: int,
        queue_capacity: int,
        rpc_timeout_seconds: float | None = None,
    ) -> None:
        if rpc_timeout_seconds is not None and rpc_timeout_seconds <= 0:
            raise ValueError("rpc_timeout_seconds must be positive when supplied")
        self._endpoint = endpoint
        self._request = aurisia_pb2.StreamRequest(
            device_id=device,
            sample_rate_hz=sample_rate_hz,
            channels=channels,
            frame_duration_ms=frame_duration_ms,
            queue_capacity=queue_capacity,
        )
        self._lock = threading.Lock()
        self._channel: grpc.Channel | None = None
        self._active_call: Any = None
        self._rpc_timeout_seconds = rpc_timeout_seconds

    def frames(self) -> Iterator[AudioFrame]:
        channel = grpc.insecure_channel(self._endpoint)
        stub = aurisia_pb2_grpc.AudioCaptureStub(channel)  # type: ignore[no-untyped-call]
        call = stub.StreamAudio(
            self._request,
            timeout=self._rpc_timeout_seconds,
        )
        with self._lock:
            self._channel = channel
            self._active_call = call
        try:
            for frame in call:
                yield AudioFrame(
                    stream_id=frame.stream_id,
                    sequence=frame.sequence,
                    captured_at_ms=frame.captured_at_ms,
                    sample_rate_hz=frame.sample_rate_hz,
                    channels=frame.channels,
                    pcm_s16le=frame.pcm_s16le,
                )
        except grpc.RpcError as exc:
            if exc.code() is not grpc.StatusCode.CANCELLED:
                raise AudioServiceUnavailable(
                    f"audio stream failed ({exc.code().name}): {exc.details()}"
                ) from exc
        finally:
            with self._lock:
                self._active_call = None
                self._channel = None
            channel.close()

    def close(self) -> None:
        with self._lock:
            if self._active_call is not None:
                self._active_call.cancel()
            if self._channel is not None:
                self._channel.close()


def list_remote_input_devices(
    endpoint: str,
    *,
    timeout_seconds: float = 5.0,
) -> tuple[AudioDevice, ...]:
    with grpc.insecure_channel(endpoint) as channel:
        stub = aurisia_pb2_grpc.AudioCaptureStub(channel)  # type: ignore[no-untyped-call]
        try:
            response = stub.ListDevices(
                aurisia_pb2.ListAudioDevicesRequest(),
                timeout=timeout_seconds,
            )
        except grpc.RpcError as exc:
            raise AudioServiceUnavailable(
                f"cannot list audio devices ({exc.code().name}): {exc.details()}"
            ) from exc
    return tuple(
        AudioDevice(
            id=device.id,
            name=device.name,
            host_api=device.host_api,
            max_input_channels=device.max_input_channels,
            default_sample_rate_hz=device.default_sample_rate_hz,
            is_default=device.is_default,
        )
        for device in response.devices
    )


def wait_for_audio_service(endpoint: str, *, timeout_seconds: float = 8.0) -> None:
    with grpc.insecure_channel(endpoint) as channel:
        try:
            grpc.channel_ready_future(channel).result(timeout=timeout_seconds)
            stub = aurisia_pb2_grpc.AudioCaptureStub(channel)  # type: ignore[no-untyped-call]
            health = stub.Health(
                aurisia_pb2.HealthRequest(),
                timeout=timeout_seconds,
            )
        except (grpc.FutureTimeoutError, grpc.RpcError) as exc:
            raise AudioServiceUnavailable(
                f"audio service at {endpoint} did not become ready"
            ) from exc
    if not health.ready:
        raise AudioServiceUnavailable(f"audio service at {endpoint} is not ready")
