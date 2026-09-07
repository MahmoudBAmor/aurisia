"""Aurisia command-line entry point."""

from __future__ import annotations

import argparse
import json
import math
import sys
from collections.abc import Sequence
from contextlib import ExitStack
from pathlib import Path

from aurisia.application.audio_process import AudioServiceProcess
from aurisia.application.demo import build_demo_pipeline
from aurisia.application.live import (
    build_live_pipeline,
    build_live_speech_engine,
    build_live_vad_engine,
    build_normalized_audio_source,
)
from aurisia.application.pipeline import PerceptionPipeline
from aurisia.application.speech_process import WhisperServerProcess
from aurisia.config import AppConfig, ConfigError, load_config
from aurisia.config.arguments import channel_count_argument, sample_rate_argument
from aurisia.contracts import VoiceActivityState, to_primitive
from aurisia.evaluation import (
    AsrEvaluationCase,
    RecordingSource,
    evaluate_asr_corpus,
    load_asr_corpus,
    record_corpus,
)
from aurisia.language import ArabicScriptNormalizer
from aurisia.services.audio.adapters import GrpcAudioSource, list_input_devices
from aurisia.services.audio.levels import rms_dbfs
from aurisia.services.speech import SpeechInferenceMeasurement, SpeechRecognitionService
from aurisia.services.vad import VadService
from aurisia.services.vad.adapters import SileroOnnxVadEngine


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Aurisia offline perception platform")
    parser.add_argument(
        "--config",
        type=Path,
        default=Path("config/aurisia.yaml"),
        help="path to the application YAML configuration",
    )
    parser.add_argument(
        "--compact",
        action="store_true",
        help="emit one compact JSON object per perception event",
    )
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--live",
        action="store_true",
        help="stream the microphone through the local audio service",
    )
    mode.add_argument(
        "--list-devices",
        action="store_true",
        help="list available input devices and exit",
    )
    mode.add_argument(
        "--probe-microphone",
        type=float,
        metavar="SECONDS",
        help="capture a short live sample and report continuity and signal level",
    )
    mode.add_argument(
        "--benchmark-vad",
        type=float,
        metavar="SECONDS",
        help="benchmark normalized live VAD probability and CPU inference latency",
    )
    mode.add_argument(
        "--record-asr-corpus",
        type=Path,
        metavar="MANIFEST",
        help="explicitly record a local, VAD-delimited ASR evaluation corpus",
    )
    mode.add_argument(
        "--evaluate-asr-corpus",
        type=Path,
        metavar="MANIFEST",
        help="replay a local ASR corpus through the configured speech adapter",
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
    parser.add_argument(
        "--recordings-root",
        type=Path,
        default=Path("recordings"),
        help="private corpus recording root; defaults to ./recordings",
    )
    parser.add_argument(
        "--recording-timeout-seconds",
        type=float,
        default=12.0,
        help="maximum listening time per corpus phrase; defaults to 12",
    )
    parser.add_argument(
        "--overwrite-recordings",
        action="store_true",
        help="replace existing corpus WAV files instead of resuming",
    )
    parser.add_argument(
        "--asr-report",
        type=Path,
        default=None,
        help="write an evaluation JSON report to a new file instead of stdout",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    try:
        config = load_config(args.config)
        if args.list_devices:
            for device in list_input_devices():
                default = " [default]" if device.is_default else ""
                print(
                    f"{device.id}: {device.name} — {device.host_api}, "
                    f"{device.max_input_channels}ch, "
                    f"{device.default_sample_rate_hz:.0f} Hz{default}"
                )
            return 0
        if args.record_asr_corpus is not None:
            return _record_asr_corpus(args, config)
        if args.evaluate_asr_corpus is not None:
            return _evaluate_asr_corpus(args, config)
        if args.live or args.probe_microphone is not None or args.benchmark_vad is not None:
            diagnostic_seconds = (
                args.probe_microphone if args.probe_microphone is not None else args.benchmark_vad
            )
            if diagnostic_seconds is not None and not 0.1 <= diagnostic_seconds <= 30.0:
                raise ValueError("diagnostic duration must be between 0.1 and 30 seconds")
            config_path = args.config.resolve()
            source = GrpcAudioSource(
                config.audio.grpc_endpoint,
                device=args.device or config.audio.device,
                sample_rate_hz=args.sample_rate_hz or config.audio.sample_rate_hz,
                channels=args.channels or config.audio.channels,
                frame_duration_ms=config.audio.frame_duration_ms,
                queue_capacity=config.runtime.audio_queue_capacity,
                rpc_timeout_seconds=(
                    diagnostic_seconds + 2.0 if diagnostic_seconds is not None else None
                ),
            )
            with ExitStack() as services:
                services.enter_context(AudioServiceProcess(config, config_path))
                if args.live and config.models.speech_adapter == "whisper_cpp":
                    services.enter_context(WhisperServerProcess(config))
                if args.probe_microphone is not None:
                    _probe_microphone(
                        source,
                        seconds=args.probe_microphone,
                        frame_duration_ms=config.audio.frame_duration_ms,
                    )
                elif args.benchmark_vad is not None:
                    _benchmark_vad(
                        source,
                        config=config,
                        seconds=args.benchmark_vad,
                    )
                else:
                    _print_events(
                        build_live_pipeline(
                            config,
                            source,
                            speech_measurement_sink=(
                                _print_asr_measurement if args.asr_metrics else None
                            ),
                        ),
                        compact=args.compact,
                    )
        else:
            _print_events(
                build_demo_pipeline(config),
                compact=args.compact,
            )
    except KeyboardInterrupt:
        print("\naurisia: stopped")
        return 130
    except (ConfigError, ValueError, RuntimeError) as exc:
        print(f"aurisia: {exc}")
        return 2
    return 0


def _record_asr_corpus(args: argparse.Namespace, config: AppConfig) -> int:
    corpus = load_asr_corpus(args.record_asr_corpus)
    _validate_corpus_locale(corpus.locale, config)
    if not 2.0 <= args.recording_timeout_seconds <= 30.0:
        raise ValueError("recording timeout must be between 2 and 30 seconds")
    output_directory = args.recordings_root / corpus.corpus_id
    print(
        "PRIVACY NOTICE: this opt-in command writes microphone recordings to:\n"
        f"  {output_directory.resolve()}\n"
        "The files stay local, are excluded from source control, and are never "
        "created by normal live mode."
    )
    try:
        confirmation = input("Type RECORD to continue, or press Enter to cancel: ")
    except EOFError:
        confirmation = ""
    if confirmation != "RECORD":
        print("aurisia: corpus recording cancelled; no recording was started")
        return 0

    config_path = args.config.resolve()
    vad_engine = build_live_vad_engine(config)

    def source_factory() -> RecordingSource:
        source = GrpcAudioSource(
            config.audio.grpc_endpoint,
            device=args.device or config.audio.device,
            sample_rate_hz=args.sample_rate_hz or config.audio.sample_rate_hz,
            channels=args.channels or config.audio.channels,
            frame_duration_ms=config.audio.frame_duration_ms,
            queue_capacity=config.runtime.audio_queue_capacity,
            rpc_timeout_seconds=args.recording_timeout_seconds + 3.0,
        )
        return build_normalized_audio_source(config, source)

    def vad_factory() -> VadService:
        return VadService(
            vad_engine,
            start_threshold=config.vad.start_probability,
            end_threshold=config.vad.end_probability,
            end_silence_frames=config.vad.end_silence_frames,
        )

    def prompt(case: AsrEvaluationCase, index: int, total: int) -> None:
        print(f"\n[{index}/{total}] {case.prompt_arabizi}")
        print(f"          {case.reference_arabic}")
        input("Press Enter when ready, wait for 'Listening', then speak: ")
        print("Listening…", flush=True)

    with AudioServiceProcess(config, config_path):
        recordings = record_corpus(
            corpus,
            output_directory,
            source_factory=source_factory,
            vad_factory=vad_factory,
            prompt=prompt,
            status_sink=print,
            pre_roll_ms=config.speech.pre_roll_ms,
            timeout_seconds=args.recording_timeout_seconds,
            overwrite=args.overwrite_recordings,
        )
    recorded_count = sum(not recording.skipped_existing for recording in recordings)
    skipped_count = len(recordings) - recorded_count
    print(
        f"Corpus ready: {recorded_count} recorded, {skipped_count} reused, "
        f"{len(recordings)} total in {output_directory}"
    )
    return 0


def _evaluate_asr_corpus(args: argparse.Namespace, config: AppConfig) -> int:
    corpus = load_asr_corpus(args.evaluate_asr_corpus)
    _validate_corpus_locale(corpus.locale, config)
    audio_directory = args.recordings_root / corpus.corpus_id
    normalizer = ArabicScriptNormalizer.from_yaml(config.language.lexicon_path)

    with ExitStack() as services:
        if config.models.speech_adapter == "whisper_cpp":
            services.enter_context(WhisperServerProcess(config))
        speech = SpeechRecognitionService(
            build_live_speech_engine(config),
            normalizer,
            locale=config.language.locale,
        )
        report = evaluate_asr_corpus(corpus, audio_directory, speech)

    report_json = json.dumps(
        report.to_dict(),
        ensure_ascii=False,
        indent=None if args.compact else 2,
    )
    if args.asr_report is None:
        print(report_json)
    else:
        report_path = args.asr_report
        report_path.parent.mkdir(parents=True, exist_ok=True)
        try:
            with report_path.open("x", encoding="utf-8", newline="\n") as output:
                output.write(report_json)
                output.write("\n")
        except FileExistsError as exc:
            raise ValueError(
                f"ASR report already exists; choose a new path: {report_path}"
            ) from exc
        print(f"ASR report written to {report_path}")
        retention = report.code_switch_retention_rate
        retention_text = "n/a" if retention is None else f"{retention:.1%}"
        print(
            f"WER {report.word_error_rate:.1%}, "
            f"CER {report.character_error_rate:.1%}, "
            f"code-switch retention {retention_text}, "
            f"mean recognition {report.mean_recognition_latency_ms:.0f} ms, "
            f"mean finalize {report.mean_finalization_latency_ms:.0f} ms"
        )
    return 0


def _validate_corpus_locale(locale: str, config: AppConfig) -> None:
    if locale != config.language.locale:
        raise ValueError(
            f"ASR corpus locale {locale} does not match configured locale "
            f"{config.language.locale}"
        )


def _print_events(pipeline: PerceptionPipeline, *, compact: bool) -> None:
    for event in pipeline.run():
        print(
            json.dumps(
                to_primitive(event),
                ensure_ascii=False,
                indent=None if compact else 2,
            )
        )


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


def _probe_microphone(
    source: GrpcAudioSource,
    *,
    seconds: float,
    frame_duration_ms: int,
) -> None:
    expected_frames = math.ceil(seconds * 1000 / frame_duration_ms)
    levels: list[float] = []
    sequences: list[int] = []
    try:
        for frame in source.frames():
            sequences.append(frame.sequence)
            levels.append(rms_dbfs(frame))
            if len(sequences) >= expected_frames:
                break
    finally:
        source.close()
    if not sequences:
        raise RuntimeError("microphone probe received no audio frames")
    discontinuities = sum(
        current != previous + 1 for previous, current in zip(sequences, sequences[1:], strict=False)
    )
    finite_levels = [level for level in levels if math.isfinite(level)]
    peak_level = max(finite_levels, default=-math.inf)
    peak_text = "-inf" if not math.isfinite(peak_level) else f"{peak_level:.1f}"
    print(
        f"microphone probe: {len(sequences)} frames, "
        f"{discontinuities} discontinuities, peak {peak_text} dBFS"
    )


def _benchmark_vad(
    source: GrpcAudioSource,
    *,
    config: AppConfig,
    seconds: float,
) -> None:
    engine = build_live_vad_engine(config)
    service = VadService(
        engine,
        start_threshold=config.vad.start_probability,
        end_threshold=config.vad.end_probability,
        end_silence_frames=config.vad.end_silence_frames,
    )
    normalized = build_normalized_audio_source(config, source)
    expected_frames = math.ceil(seconds * 1_000 / config.normalization.frame_duration_ms)
    probabilities: list[float] = []
    speech_starts = 0
    try:
        for frame in normalized.frames():
            activity = service.observe(frame)
            probabilities.append(activity.probability)
            if activity.state is VoiceActivityState.SPEECH_START:
                speech_starts += 1
            if len(probabilities) >= expected_frames:
                break
    finally:
        source.close()
    if not probabilities:
        raise RuntimeError("VAD benchmark received no normalized audio frames")

    details = ""
    if isinstance(engine, SileroOnnxVadEngine):
        metrics = engine.metrics()
        details = (
            f", {metrics.inference_count} inferences, "
            f"mean {metrics.mean_inference_ms:.3f} ms, "
            f"max {metrics.maximum_inference_ms:.3f} ms"
        )
    print(
        f"VAD benchmark: {engine.model.model_id}@{engine.model.version}, "
        f"{len(probabilities)} frames, {speech_starts} speech starts, "
        f"peak probability {max(probabilities):.3f}{details}"
    )
