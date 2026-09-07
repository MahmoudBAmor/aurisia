"""Stateful CPU-only Silero VAD adapter using ONNX Runtime directly."""

from __future__ import annotations

import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any

from aurisia.contracts import AudioFrame, ModelDescriptor


class VadInferenceUnavailable(RuntimeError):
    """Raised when the optional ONNX inference backend is unavailable."""


@dataclass(frozen=True, slots=True)
class VadInferenceMetrics:
    inference_count: int
    total_inference_ns: int
    maximum_inference_ns: int

    @property
    def mean_inference_ms(self) -> float:
        if self.inference_count == 0:
            return 0.0
        return self.total_inference_ns / self.inference_count / 1_000_000

    @property
    def maximum_inference_ms(self) -> float:
        return self.maximum_inference_ns / 1_000_000


class SileroOnnxVadEngine:
    """Run streaming Silero inference over canonical 16 kHz mono PCM."""

    _sample_rate_hz = 16_000
    _window_samples = 512
    _context_samples = 64

    def __init__(
        self,
        model_path: Path,
        model: ModelDescriptor,
        *,
        session: Any = None,
    ) -> None:
        numpy, onnxruntime = _load_inference_backend()
        if session is None:
            if not model_path.is_file():
                raise FileNotFoundError(f"Silero model artifact was not found: {model_path}")
            options = onnxruntime.SessionOptions()
            options.inter_op_num_threads = 1
            options.intra_op_num_threads = 1
            options.execution_mode = onnxruntime.ExecutionMode.ORT_SEQUENTIAL
            session = onnxruntime.InferenceSession(
                str(model_path),
                sess_options=options,
                providers=["CPUExecutionProvider"],
            )
        self._numpy = numpy
        self._session = session
        self._model = model
        self._pending = numpy.empty(0, dtype=numpy.float32)
        self._state = numpy.zeros((2, 1, 128), dtype=numpy.float32)
        self._context = numpy.zeros((1, self._context_samples), dtype=numpy.float32)
        self._stream_id: str | None = None
        self._previous_sequence: int | None = None
        self._inference_count = 0
        self._total_inference_ns = 0
        self._maximum_inference_ns = 0

    @property
    def model(self) -> ModelDescriptor:
        return self._model

    def speech_probability(self, frame: AudioFrame) -> float | None:
        self._validate_frame(frame)
        if self._stream_id is not None and (
            frame.stream_id != self._stream_id
            or (
                self._previous_sequence is not None
                and frame.sequence != self._previous_sequence + 1
            )
        ):
            self.reset()
        self._stream_id = frame.stream_id
        self._previous_sequence = frame.sequence

        samples = (
            self._numpy.frombuffer(frame.pcm_s16le, dtype="<i2").astype(self._numpy.float32)
            / 32_768.0
        )
        self._pending = self._numpy.concatenate((self._pending, samples))
        probabilities: list[float] = []
        while self._pending.size >= self._window_samples:
            chunk = self._pending[: self._window_samples]
            self._pending = self._pending[self._window_samples :]
            probabilities.append(self._infer(chunk))
        return max(probabilities) if probabilities else None

    def reset(self) -> None:
        self._pending = self._numpy.empty(0, dtype=self._numpy.float32)
        self._state.fill(0)
        self._context.fill(0)
        self._stream_id = None
        self._previous_sequence = None

    def metrics(self) -> VadInferenceMetrics:
        return VadInferenceMetrics(
            inference_count=self._inference_count,
            total_inference_ns=self._total_inference_ns,
            maximum_inference_ns=self._maximum_inference_ns,
        )

    def _infer(self, chunk: Any) -> float:
        model_input = self._numpy.concatenate(
            (self._context, chunk.reshape(1, -1)),
            axis=1,
        ).astype(self._numpy.float32, copy=False)
        started_ns = time.perf_counter_ns()
        outputs = self._session.run(
            None,
            {
                "input": model_input,
                "state": self._state,
                "sr": self._numpy.array(self._sample_rate_hz, dtype=self._numpy.int64),
            },
        )
        elapsed_ns = time.perf_counter_ns() - started_ns
        self._inference_count += 1
        self._total_inference_ns += elapsed_ns
        self._maximum_inference_ns = max(self._maximum_inference_ns, elapsed_ns)
        probability = float(self._numpy.asarray(outputs[0]).reshape(-1)[0])
        self._state = self._numpy.asarray(outputs[1], dtype=self._numpy.float32)
        self._context = model_input[:, -self._context_samples :]
        return min(1.0, max(0.0, probability))

    def _validate_frame(self, frame: AudioFrame) -> None:
        if frame.sample_rate_hz != self._sample_rate_hz or frame.channels != 1:
            raise ValueError("Silero VAD requires normalized 16000 Hz mono audio")


def _load_inference_backend() -> tuple[Any, Any]:
    try:
        import numpy
        import onnxruntime  # type: ignore[import-untyped]
    except ImportError as exc:
        raise VadInferenceUnavailable("Silero VAD requires Aurisia's 'inference' extra") from exc
    return numpy, onnxruntime
