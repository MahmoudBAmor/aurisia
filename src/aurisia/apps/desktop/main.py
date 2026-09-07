"""PySide6/QML desktop HUD entry point."""

from __future__ import annotations

import argparse
import os
import sys
import threading
from collections.abc import Sequence
from pathlib import Path

from aurisia.application.audio_process import AudioServiceProcess
from aurisia.application.demo import build_demo_pipeline
from aurisia.application.live import build_live_pipeline
from aurisia.application.speech_process import WhisperServerProcess
from aurisia.config import load_config
from aurisia.config.arguments import channel_count_argument, sample_rate_argument
from aurisia.services.audio.adapters import GrpcAudioSource
from aurisia.services.speech import SpeechInferenceMeasurement


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Aurisia transparent desktop HUD")
    parser.add_argument(
        "--config",
        type=Path,
        default=Path("config/aurisia.yaml"),
        help="path to the application YAML configuration",
    )
    parser.add_argument(
        "--smoke-test",
        action="store_true",
        help="load the HUD offscreen and exit after validating its QML",
    )
    parser.add_argument(
        "--live",
        action="store_true",
        help="capture the selected microphone through the local audio service",
    )
    parser.add_argument(
        "--device",
        default=None,
        help="microphone id or unique name fragment; defaults to configuration",
    )
    parser.add_argument(
        "--sample-rate-hz",
        type=sample_rate_argument,
        default=None,
        help="capture sample rate; defaults to configuration",
    )
    parser.add_argument(
        "--channels",
        type=channel_count_argument,
        default=None,
        help="capture channel count; defaults to configuration",
    )
    parser.add_argument(
        "--asr-metrics",
        action="store_true",
        help="print ASR latency and real-time factor to stderr",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if args.smoke_test:
        os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
    try:
        from PySide6.QtCore import QTimer, QUrl
        from PySide6.QtGui import QGuiApplication
        from PySide6.QtQml import QQmlApplicationEngine
    except ImportError:
        print(
            "aurisia-desktop: PySide6 is not installed. "
            "Install the desktop extra with 'pip install -e .[desktop]'."
        )
        return 2

    from .qt_bridge import HudBridge

    config_path = args.config.resolve()
    config = load_config(config_path)

    app = QGuiApplication(["aurisia-desktop"])
    engine = QQmlApplicationEngine()
    bridge = HudBridge()
    engine.setInitialProperties(
        {
            "bridge": bridge,
            "inputTransparent": config.hud.click_through,
        }
    )

    qml_path = Path(__file__).with_name("qml") / "Main.qml"
    engine.load(QUrl.fromLocalFile(str(qml_path.resolve())))
    if not engine.rootObjects():
        return 2

    timer = QTimer()
    audio_process: AudioServiceProcess | None = None
    speech_process: WhisperServerProcess | None = None
    audio_source: GrpcAudioSource | None = None
    if args.live:
        audio_process = AudioServiceProcess(config, config_path)
        if config.models.speech_adapter == "whisper_cpp":
            speech_process = WhisperServerProcess(config)
        audio_source = GrpcAudioSource(
            config.audio.grpc_endpoint,
            device=args.device or config.audio.device,
            sample_rate_hz=args.sample_rate_hz or config.audio.sample_rate_hz,
            channels=args.channels or config.audio.channels,
            frame_duration_ms=config.audio.frame_duration_ms,
            queue_capacity=config.runtime.audio_queue_capacity,
        )
        try:
            if speech_process is not None:
                speech_process.start()
            pipeline = build_live_pipeline(
                config,
                audio_source,
                speech_measurement_sink=(
                    _print_asr_measurement if args.asr_metrics else None
                ),
            )
            audio_process.start()
        except Exception as exc:
            audio_source.close()
            audio_process.stop()
            if speech_process is not None:
                speech_process.stop()
            print(f"aurisia-desktop: cannot start live pipeline: {exc}")
            return 2

        def run_live_pipeline() -> None:
            try:
                for event in pipeline.run():
                    bridge.publish(event)
            except Exception as exc:
                print(f"aurisia-desktop: live pipeline stopped: {exc}")

        threading.Thread(
            target=run_live_pipeline,
            name="aurisia-live-pipeline",
            daemon=True,
        ).start()
        app.aboutToQuit.connect(audio_source.close)
        app.aboutToQuit.connect(audio_process.stop)
        if speech_process is not None:
            app.aboutToQuit.connect(speech_process.stop)
    else:
        events = tuple(build_demo_pipeline(config).run())
        if not events:
            print("aurisia-desktop: the configured pipeline produced no perception events")
            return 2
        state = {"index": 0}

        def show_next_event() -> None:
            bridge.show(events[state["index"]])
            state["index"] = (state["index"] + 1) % len(events)

        timer.setInterval(2200)
        timer.timeout.connect(show_next_event)
        show_next_event()
        timer.start()
    if args.smoke_test:
        QTimer.singleShot(1200 if args.live else 100, app.quit)
    engine.quit.connect(app.quit)
    return app.exec()


def _print_asr_measurement(measurement: SpeechInferenceMeasurement) -> None:
    finalization = (
        ""
        if measurement.finalization_latency_ms is None
        else f", finalize {measurement.finalization_latency_ms:.0f} ms"
    )
    print(
        f"ASR: {measurement.inference_latency_ms:.0f} ms inference for "
        f"{measurement.audio_duration_ms} ms audio "
        f"(RTF {measurement.real_time_factor:.2f}{finalization})",
        file=sys.stderr,
        flush=True,
    )
