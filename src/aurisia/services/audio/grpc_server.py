"""Loopback gRPC host for the independent audio capture service."""

from __future__ import annotations

import argparse
from collections.abc import Callable, Iterator, Sequence
from concurrent import futures
from pathlib import Path

import grpc
from grpc_health.v1 import health, health_pb2, health_pb2_grpc

from aurisia import __version__
from aurisia.config import AppConfig, load_config
from aurisia.contracts import AudioDevice
from aurisia.v1 import aurisia_pb2, aurisia_pb2_grpc

from .adapters.sounddevice_source import (
    AudioBackendUnavailable,
    AudioDeviceSelectionError,
    SoundDeviceAudioSource,
    list_input_devices,
)
from .ports import AudioSource

SourceFactory = Callable[[aurisia_pb2.StreamRequest], AudioSource]
DeviceProvider = Callable[[], tuple[AudioDevice, ...]]


class AudioCaptureGrpcService:
    """Transport adapter around the audio source port."""

    def __init__(
        self,
        config: AppConfig,
        *,
        source_factory: SourceFactory | None = None,
        device_provider: DeviceProvider = list_input_devices,
    ) -> None:
        self._config = config
        self._source_factory = source_factory or self._default_source_factory
        self._device_provider = device_provider

    def StreamAudio(
        self,
        request: aurisia_pb2.StreamRequest,
        context: grpc.ServicerContext,
    ) -> Iterator[aurisia_pb2.AudioFrame]:
        source: AudioSource | None = None
        try:
            source = self._source_factory(request)
            for frame in source.frames():
                if not context.is_active():
                    break
                yield aurisia_pb2.AudioFrame(
                    stream_id=frame.stream_id,
                    sequence=frame.sequence,
                    captured_at_ms=frame.captured_at_ms,
                    sample_rate_hz=frame.sample_rate_hz,
                    channels=frame.channels,
                    pcm_s16le=frame.pcm_s16le,
                )
        except AudioDeviceSelectionError as exc:
            context.abort(grpc.StatusCode.INVALID_ARGUMENT, str(exc))
        except AudioBackendUnavailable as exc:
            context.abort(grpc.StatusCode.FAILED_PRECONDITION, str(exc))
        finally:
            closer = getattr(source, "close", None)
            if closer is not None:
                closer()

    def ListDevices(
        self,
        request: aurisia_pb2.ListAudioDevicesRequest,
        context: grpc.ServicerContext,
    ) -> aurisia_pb2.AudioDeviceList:
        del request
        try:
            devices = self._device_provider()
        except AudioBackendUnavailable as exc:
            context.abort(grpc.StatusCode.FAILED_PRECONDITION, str(exc))
        return aurisia_pb2.AudioDeviceList(
            devices=[
                aurisia_pb2.AudioDevice(
                    id=device.id,
                    name=device.name,
                    host_api=device.host_api,
                    max_input_channels=device.max_input_channels,
                    default_sample_rate_hz=device.default_sample_rate_hz,
                    is_default=device.is_default,
                )
                for device in devices
            ]
        )

    def Health(
        self,
        request: aurisia_pb2.HealthRequest,
        context: grpc.ServicerContext,
    ) -> aurisia_pb2.HealthResponse:
        del request, context
        return aurisia_pb2.HealthResponse(
            service_name="audio_capture",
            version=__version__,
            ready=True,
            capabilities=[
                "audio.pcm_s16le",
                "audio.device_listing",
                "audio.reconnect",
                "transport.grpc_streaming",
            ],
        )

    def _default_source_factory(
        self,
        request: aurisia_pb2.StreamRequest,
    ) -> SoundDeviceAudioSource:
        config = self._config
        return SoundDeviceAudioSource(
            device=request.device_id or config.audio.device,
            sample_rate_hz=request.sample_rate_hz or config.audio.sample_rate_hz,
            channels=request.channels or config.audio.channels,
            frame_duration_ms=(request.frame_duration_ms or config.audio.frame_duration_ms),
            queue_capacity=(request.queue_capacity or config.runtime.audio_queue_capacity),
            reconnect_delay_ms=config.audio.reconnect_delay_ms,
        )


def create_server(
    config: AppConfig,
    *,
    endpoint: str | None = None,
    source_factory: SourceFactory | None = None,
    device_provider: DeviceProvider = list_input_devices,
) -> tuple[grpc.Server, int]:
    server = grpc.server(
        futures.ThreadPoolExecutor(max_workers=4, thread_name_prefix="aurisia-audio"),
        options=(
            ("grpc.max_send_message_length", 4 * 1024 * 1024),
            ("grpc.max_receive_message_length", 4 * 1024 * 1024),
        ),
    )
    service = AudioCaptureGrpcService(
        config,
        source_factory=source_factory,
        device_provider=device_provider,
    )
    aurisia_pb2_grpc.add_AudioCaptureServicer_to_server(  # type: ignore[no-untyped-call]
        service,
        server,
    )

    health_service = health.HealthServicer()
    health_pb2_grpc.add_HealthServicer_to_server(health_service, server)
    service_name = "aurisia.v1.AudioCapture"
    health_service.set("", health_pb2.HealthCheckResponse.SERVING)
    health_service.set(service_name, health_pb2.HealthCheckResponse.SERVING)

    bound_port = server.add_insecure_port(endpoint or config.audio.grpc_endpoint)
    if bound_port == 0:
        raise RuntimeError("failed to bind the loopback audio service endpoint")
    return server, bound_port


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Aurisia local audio capture service")
    parser.add_argument(
        "--config",
        type=Path,
        default=Path("config/aurisia.yaml"),
        help="path to the application YAML configuration",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    config = load_config(args.config)
    server, _ = create_server(config)
    server.start()
    try:
        server.wait_for_termination()
    except KeyboardInterrupt:
        server.stop(grace=1.0).wait()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
