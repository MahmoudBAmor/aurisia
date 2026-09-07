"""Persistent offline Vosk adapter for Tunisian Kaldi model packs."""

from __future__ import annotations

import importlib
import json
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Protocol, cast

from aurisia.contracts import ModelDescriptor, SpeechSegment

from ..measurements import SpeechInferenceMeasurement
from ..ports import SpeechHypothesis, StreamingSpeechSession


class VoskRuntimeUnavailable(RuntimeError):
    """Raised when Vosk cannot load its runtime, model, or decoder result."""


class _VoskRecognizer(Protocol):
    def SetWords(self, enabled: bool) -> None: ...

    def AcceptWaveform(self, pcm_s16le: bytes) -> bool: ...

    def Result(self) -> str: ...

    def PartialResult(self) -> str: ...

    def FinalResult(self) -> str: ...


ModelFactory = Callable[[Path], Any]
RecognizerFactory = Callable[[Any, float], _VoskRecognizer]


class VoskSpeechEngine:
    """Transcribe canonical PCM through one persistent Vosk model."""

    def __init__(
        self,
        *,
        model_directory: Path,
        model: ModelDescriptor,
        supported_locale: str,
        sample_rate_hz: int,
        channels: int,
        model_factory: ModelFactory | None = None,
        recognizer_factory: RecognizerFactory | None = None,
        measurement_sink: Callable[[SpeechInferenceMeasurement], None] | None = None,
    ) -> None:
        if not model_directory.is_dir():
            raise VoskRuntimeUnavailable(
                f"Vosk model directory is missing: {model_directory}"
            )
        if sample_rate_hz <= 0:
            raise ValueError("Vosk sample rate must be positive")
        if channels != 1:
            raise ValueError("Vosk currently requires canonical mono audio")
        if not supported_locale:
            raise ValueError("supported locale must not be empty")

        if model_factory is None or recognizer_factory is None:
            runtime_model_factory, runtime_recognizer_factory = _load_vosk_runtime()
            model_factory = model_factory or runtime_model_factory
            recognizer_factory = recognizer_factory or runtime_recognizer_factory
        try:
            self._model_handle = model_factory(model_directory)
        except Exception as exc:
            raise VoskRuntimeUnavailable(f"cannot initialize Vosk model: {exc}") from exc

        self._recognizer_factory = recognizer_factory
        self._model = model
        self._supported_locale = supported_locale
        self._sample_rate_hz = sample_rate_hz
        self._channels = channels
        self._measurement_sink = measurement_sink

    @property
    def model(self) -> ModelDescriptor:
        return self._model

    def transcribe(self, segment: SpeechSegment, locale: str) -> SpeechHypothesis:
        session = self.start_stream(
            locale,
            segment.sample_rate_hz,
            segment.channels,
        )
        session.accept_pcm(segment.pcm_s16le)
        return session.finish(segment.end_time_ms - segment.start_time_ms)

    def start_stream(
        self,
        locale: str,
        sample_rate_hz: int,
        channels: int,
    ) -> StreamingSpeechSession:
        """Create a decoder so recognition work can run alongside capture."""

        if locale != self._supported_locale:
            raise ValueError(
                f"Vosk adapter supports {self._supported_locale}, got {locale}"
            )
        if (sample_rate_hz, channels) != (
            self._sample_rate_hz,
            self._channels,
        ):
            raise ValueError(
                "speech segment does not match the Vosk audio contract: "
                f"expected {self._sample_rate_hz} Hz/{self._channels}ch, "
                f"got {sample_rate_hz} Hz/{channels}ch"
            )

        started_ns = time.perf_counter_ns()
        try:
            recognizer = self._recognizer_factory(
                self._model_handle,
                float(self._sample_rate_hz),
            )
            recognizer.SetWords(True)
        except Exception as exc:
            raise VoskRuntimeUnavailable(
                f"cannot initialize Vosk recognizer: {exc}"
            ) from exc
        initialization_ns = time.perf_counter_ns() - started_ns
        return _VoskDecoderSession(
            recognizer,
            initialization_ns=initialization_ns,
            measurement_sink=self._measurement_sink,
        )


class _VoskDecoderSession:
    """Own one utterance decoder and its model-neutral measurements."""

    def __init__(
        self,
        recognizer: _VoskRecognizer,
        *,
        initialization_ns: int,
        measurement_sink: Callable[[SpeechInferenceMeasurement], None] | None,
    ) -> None:
        self._recognizer = recognizer
        self._inference_ns = initialization_ns
        self._measurement_sink = measurement_sink
        self._finished = False
        self._completed_results: list[_ParsedVoskResult] = []

    def accept_pcm(self, pcm_s16le: bytes) -> None:
        if self._finished:
            raise RuntimeError("Vosk decoder session is already finished")
        started_ns = time.perf_counter_ns()
        try:
            endpoint_reached = self._recognizer.AcceptWaveform(pcm_s16le)
            if endpoint_reached:
                self._completed_results.append(
                    _parse_result(self._recognizer.Result())
                )
        except VoskRuntimeUnavailable:
            raise
        except Exception as exc:
            raise VoskRuntimeUnavailable(f"Vosk inference failed: {exc}") from exc
        self._inference_ns += time.perf_counter_ns() - started_ns

    def finish(self, audio_duration_ms: int) -> SpeechHypothesis:
        if self._finished:
            raise RuntimeError("Vosk decoder session is already finished")
        if audio_duration_ms < 0:
            raise ValueError("audio duration must not be negative")
        self._finished = True

        started_ns = time.perf_counter_ns()
        try:
            final_result = _parse_result(self._recognizer.FinalResult())
            hypothesis = _combine_results([*self._completed_results, final_result])
        except VoskRuntimeUnavailable:
            raise
        except Exception as exc:
            raise VoskRuntimeUnavailable(f"Vosk inference failed: {exc}") from exc
        finalization_ns = time.perf_counter_ns() - started_ns
        self._inference_ns += finalization_ns

        if self._measurement_sink is not None:
            self._measurement_sink(
                SpeechInferenceMeasurement(
                    audio_duration_ms=audio_duration_ms,
                    inference_latency_ms=self._inference_ns / 1_000_000,
                    finalization_latency_ms=finalization_ns / 1_000_000,
                )
            )
        return hypothesis

    def preview(self) -> SpeechHypothesis:
        if self._finished:
            raise RuntimeError("Vosk decoder session is already finished")
        started_ns = time.perf_counter_ns()
        try:
            partial_result = _parse_partial_result(
                self._recognizer.PartialResult()
            )
        except VoskRuntimeUnavailable:
            raise
        except Exception as exc:
            raise VoskRuntimeUnavailable(f"Vosk inference failed: {exc}") from exc
        self._inference_ns += time.perf_counter_ns() - started_ns
        return _combine_results([*self._completed_results, partial_result])


def _load_vosk_runtime() -> tuple[ModelFactory, RecognizerFactory]:
    try:
        vosk = importlib.import_module("vosk")
    except ImportError as exc:
        raise VoskRuntimeUnavailable(
            "vosk 0.3.45 is not installed; reinstall Aurisia's inference extra"
        ) from exc
    vosk.SetLogLevel(-1)

    def model_factory(path: Path) -> Any:
        return vosk.Model(str(path))

    def recognizer_factory(model: Any, sample_rate_hz: float) -> _VoskRecognizer:
        return cast(_VoskRecognizer, vosk.KaldiRecognizer(model, sample_rate_hz))

    return model_factory, recognizer_factory


@dataclass(frozen=True, slots=True)
class _ParsedVoskResult:
    text: str
    confidences: tuple[float, ...]


def _parse_result(value: str) -> _ParsedVoskResult:
    try:
        result = json.loads(value)
    except json.JSONDecodeError as exc:
        raise VoskRuntimeUnavailable("Vosk returned invalid JSON") from exc
    if not isinstance(result, dict) or not isinstance(result.get("text"), str):
        raise VoskRuntimeUnavailable("Vosk result does not contain text")

    words = result.get("result")
    confidences: list[float] = []
    if isinstance(words, list):
        for word in words:
            if not isinstance(word, dict):
                continue
            confidence = word.get("conf")
            if isinstance(confidence, (int, float)) and not isinstance(confidence, bool):
                confidences.append(min(1.0, max(0.0, float(confidence))))
    return _ParsedVoskResult(
        text=result["text"].strip(),
        confidences=tuple(confidences),
    )


def _parse_partial_result(value: str) -> _ParsedVoskResult:
    try:
        result = json.loads(value)
    except json.JSONDecodeError as exc:
        raise VoskRuntimeUnavailable("Vosk returned invalid partial JSON") from exc
    if not isinstance(result, dict) or not isinstance(result.get("partial"), str):
        raise VoskRuntimeUnavailable("Vosk partial result does not contain text")
    return _ParsedVoskResult(
        text=result["partial"].strip(),
        confidences=(),
    )


def _combine_results(results: list[_ParsedVoskResult]) -> SpeechHypothesis:
    text = " ".join(result.text for result in results if result.text)
    confidences = [
        confidence
        for result in results
        for confidence in result.confidences
    ]
    return SpeechHypothesis(
        text=text,
        confidence=sum(confidences) / len(confidences) if confidences else None,
    )
