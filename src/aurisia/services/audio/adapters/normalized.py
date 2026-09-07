"""Canonical PCM normalization adapter for model-facing audio."""

from __future__ import annotations

from collections.abc import Iterator
from typing import Any

from aurisia.contracts import AudioFrame

from ..ports import AudioSource


class AudioNormalizationUnavailable(RuntimeError):
    """Raised when the optional normalization backend is unavailable."""


class NormalizingAudioSource:
    """Downmix and resample an AudioSource into fixed-duration mono PCM frames."""

    def __init__(
        self,
        source: AudioSource,
        *,
        sample_rate_hz: int = 16_000,
        frame_duration_ms: int = 20,
        quality: str = "HQ",
    ) -> None:
        if sample_rate_hz <= 0:
            raise ValueError("sample_rate_hz must be positive")
        if frame_duration_ms <= 0:
            raise ValueError("frame_duration_ms must be positive")
        samples_per_frame = sample_rate_hz * frame_duration_ms // 1_000
        if samples_per_frame <= 0:
            raise ValueError("frame duration is too short for the target sample rate")
        if quality not in {"QQ", "LQ", "MQ", "HQ", "VHQ"}:
            raise ValueError("unsupported SoXR quality")

        self._source = source
        self._sample_rate_hz = sample_rate_hz
        self._frame_duration_ms = frame_duration_ms
        self._samples_per_frame = samples_per_frame
        self._quality = quality

    def frames(self) -> Iterator[AudioFrame]:
        numpy, soxr = _load_normalization_backend()
        source_format: tuple[int, int] | None = None
        resampler: Any = None
        pending = numpy.empty(0, dtype=numpy.float32)
        output_sequence = 0
        output_stream_id: str | None = None
        output_origin_ms = 0
        previous_source_sequence: int | None = None

        for frame in self._source.frames():
            current_format = (frame.sample_rate_hz, frame.channels)
            if source_format is None:
                source_format = current_format
                output_stream_id = f"{frame.stream_id}:{self._sample_rate_hz}hz-mono"
                output_origin_ms = frame.captured_at_ms
                resampler = self._new_resampler(soxr, frame.sample_rate_hz)
            elif current_format != source_format:
                raise ValueError("audio format changed during normalization")

            if (
                previous_source_sequence is not None
                and frame.sequence != previous_source_sequence + 1
            ):
                pending = numpy.empty(0, dtype=numpy.float32)
                if resampler is not None:
                    resampler.clear()
                elapsed_ms = max(0, frame.captured_at_ms - output_origin_ms)
                output_sequence = max(
                    output_sequence,
                    elapsed_ms // self._frame_duration_ms,
                )
            previous_source_sequence = frame.sequence

            mono = _decode_mono_float32(numpy, frame)
            normalized = mono if resampler is None else resampler.resample_chunk(mono, last=False)
            if normalized.size:
                pending = numpy.concatenate((pending, normalized))

            while pending.size >= self._samples_per_frame:
                samples = pending[: self._samples_per_frame]
                pending = pending[self._samples_per_frame :]
                yield _encode_frame(
                    numpy,
                    samples,
                    stream_id=_required_stream_id(output_stream_id),
                    sequence=output_sequence,
                    captured_at_ms=(output_origin_ms + output_sequence * self._frame_duration_ms),
                    sample_rate_hz=self._sample_rate_hz,
                )
                output_sequence += 1

        if source_format is None:
            return
        if resampler is not None:
            flushed = resampler.resample_chunk(
                numpy.empty(0, dtype=numpy.float32),
                last=True,
            )
            if flushed.size:
                pending = numpy.concatenate((pending, flushed))
        while pending.size >= self._samples_per_frame:
            samples = pending[: self._samples_per_frame]
            pending = pending[self._samples_per_frame :]
            yield _encode_frame(
                numpy,
                samples,
                stream_id=_required_stream_id(output_stream_id),
                sequence=output_sequence,
                captured_at_ms=(output_origin_ms + output_sequence * self._frame_duration_ms),
                sample_rate_hz=self._sample_rate_hz,
            )
            output_sequence += 1
        if pending.size:
            padded = numpy.pad(
                pending,
                (0, self._samples_per_frame - pending.size),
            )
            yield _encode_frame(
                numpy,
                padded,
                stream_id=_required_stream_id(output_stream_id),
                sequence=output_sequence,
                captured_at_ms=output_origin_ms + output_sequence * self._frame_duration_ms,
                sample_rate_hz=self._sample_rate_hz,
            )

    def close(self) -> None:
        """Close the wrapped platform source when it exposes a lifecycle hook."""

        closer = getattr(self._source, "close", None)
        if closer is not None:
            closer()

    def _new_resampler(self, soxr: Any, source_sample_rate_hz: int) -> Any:
        if source_sample_rate_hz == self._sample_rate_hz:
            return None
        return soxr.ResampleStream(
            source_sample_rate_hz,
            self._sample_rate_hz,
            1,
            dtype="float32",
            quality=self._quality,
        )


def _decode_mono_float32(numpy: Any, frame: AudioFrame) -> Any:
    interleaved = numpy.frombuffer(frame.pcm_s16le, dtype="<i2")
    channels = interleaved.reshape((-1, frame.channels)).astype(numpy.float32)
    return channels.mean(axis=1) / 32_768.0


def _encode_frame(
    numpy: Any,
    samples: Any,
    *,
    stream_id: str,
    sequence: int,
    captured_at_ms: int,
    sample_rate_hz: int,
) -> AudioFrame:
    pcm = numpy.clip(
        numpy.rint(samples * 32_768.0),
        -32_768,
        32_767,
    ).astype("<i2")
    return AudioFrame(
        stream_id=stream_id,
        sequence=sequence,
        captured_at_ms=captured_at_ms,
        sample_rate_hz=sample_rate_hz,
        channels=1,
        pcm_s16le=pcm.tobytes(),
    )


def _required_stream_id(value: str | None) -> str:
    if value is None:  # pragma: no cover - guarded by the first source frame
        raise RuntimeError("normalizer has no source stream")
    return value


def _load_normalization_backend() -> tuple[Any, Any]:
    try:
        import numpy
        import soxr  # type: ignore[import-untyped]
    except ImportError as exc:
        raise AudioNormalizationUnavailable(
            "audio normalization requires Aurisia's 'inference' extra"
        ) from exc
    return numpy, soxr
