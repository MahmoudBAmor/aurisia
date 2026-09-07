"""CPU-only Moonshine ASR adapter through the pinned sherpa-onnx runtime."""

from __future__ import annotations

import importlib
import time
from collections.abc import Callable
from pathlib import Path
from typing import Any, Protocol, cast

import numpy as np
import numpy.typing as npt

from aurisia.contracts import ModelDescriptor, SpeechSegment

from ..measurements import SpeechInferenceMeasurement
from ..ports import SpeechHypothesis


class MoonshineRuntimeUnavailable(RuntimeError):
    """Raised when the optional Moonshine runtime cannot perform inference."""


class _RecognitionResult(Protocol):
    text: str


class _OfflineStream(Protocol):
    @property
    def result(self) -> _RecognitionResult: ...

    def accept_waveform(
        self,
        sample_rate: int,
        waveform: npt.NDArray[np.float32],
    ) -> None: ...


class _OfflineRecognizer(Protocol):
    def create_stream(self) -> _OfflineStream: ...

    def decode_stream(self, stream: _OfflineStream) -> None: ...


RecognizerFactory = Callable[[Path, Path, Path, int], _OfflineRecognizer]


class MoonshineOnnxSpeechEngine:
    """Transcribe canonical PCM with a persistent in-process native recognizer."""

    def __init__(
        self,
        *,
        encoder_path: Path,
        decoder_path: Path,
        tokens_path: Path,
        model: ModelDescriptor,
        supported_locale: str,
        sample_rate_hz: int,
        channels: int,
        threads: int,
        recognizer_factory: RecognizerFactory | None = None,
        measurement_sink: Callable[[SpeechInferenceMeasurement], None] | None = None,
    ) -> None:
        if sample_rate_hz <= 0:
            raise ValueError("Moonshine sample rate must be positive")
        if channels != 1:
            raise ValueError("Moonshine currently requires canonical mono audio")
        if threads <= 0:
            raise ValueError("Moonshine thread count must be positive")
        if not supported_locale:
            raise ValueError("supported locale must not be empty")
        for path in (encoder_path, decoder_path, tokens_path):
            if not path.is_file():
                raise MoonshineRuntimeUnavailable(f"Moonshine artifact is missing: {path}")

        factory = recognizer_factory or _create_recognizer
        try:
            self._recognizer = factory(
                encoder_path,
                decoder_path,
                tokens_path,
                threads,
            )
        except MoonshineRuntimeUnavailable:
            raise
        except Exception as exc:
            raise MoonshineRuntimeUnavailable(
                f"cannot initialize Moonshine recognizer: {exc}"
            ) from exc

        self._model = model
        self._supported_locale = supported_locale
        self._sample_rate_hz = sample_rate_hz
        self._channels = channels
        self._measurement_sink = measurement_sink

    @property
    def model(self) -> ModelDescriptor:
        return self._model

    def transcribe(self, segment: SpeechSegment, locale: str) -> SpeechHypothesis:
        if locale != self._supported_locale:
            raise ValueError(
                f"Moonshine adapter supports {self._supported_locale}, got {locale}"
            )
        if (segment.sample_rate_hz, segment.channels) != (
            self._sample_rate_hz,
            self._channels,
        ):
            raise ValueError(
                "speech segment does not match the Moonshine audio contract: "
                f"expected {self._sample_rate_hz} Hz/{self._channels}ch, "
                f"got {segment.sample_rate_hz} Hz/{segment.channels}ch"
            )

        waveform = (
            np.frombuffer(segment.pcm_s16le, dtype="<i2")
            .astype(np.float32)
            .reshape(-1)
        )
        waveform /= 32_768.0
        stream = self._recognizer.create_stream()
        stream.accept_waveform(segment.sample_rate_hz, waveform)
        started_ns = time.perf_counter_ns()
        try:
            self._recognizer.decode_stream(stream)
        except Exception as exc:
            raise MoonshineRuntimeUnavailable(
                f"Moonshine inference failed: {exc}"
            ) from exc
        elapsed_ms = (time.perf_counter_ns() - started_ns) / 1_000_000
        if self._measurement_sink is not None:
            self._measurement_sink(
                SpeechInferenceMeasurement(
                    audio_duration_ms=segment.end_time_ms - segment.start_time_ms,
                    inference_latency_ms=elapsed_ms,
                )
            )
        return SpeechHypothesis(text=stream.result.text.strip(), confidence=None)


def _create_recognizer(
    encoder_path: Path,
    decoder_path: Path,
    tokens_path: Path,
    threads: int,
) -> _OfflineRecognizer:
    try:
        sherpa = importlib.import_module("sherpa_onnx")
        native = importlib.import_module("sherpa_onnx.lib._sherpa_onnx")
    except ImportError as exc:
        raise MoonshineRuntimeUnavailable(
            "sherpa-onnx 1.13.2 is not installed; reinstall Aurisia's inference extra"
        ) from exc

    moonshine: Any = sherpa.OfflineMoonshineModelConfig()
    moonshine.encoder = str(encoder_path)
    moonshine.merged_decoder = str(decoder_path)

    model: Any = sherpa.OfflineModelConfig()
    model.moonshine = moonshine
    model.tokens = str(tokens_path)
    model.num_threads = threads
    model.provider = "cpu"

    features: Any = sherpa.FeatureExtractorConfig()
    features.sampling_rate = 16_000
    features.feature_dim = 80

    config: Any = sherpa.OfflineRecognizerConfig()
    config.model_config = model
    config.feat_config = features
    config.decoding_method = "greedy_search"
    return cast(_OfflineRecognizer, native.OfflineRecognizer(config))
