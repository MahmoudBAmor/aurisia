"""Strict model-pack manifest loading and artifact verification."""

from __future__ import annotations

import hashlib
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

from aurisia.contracts import ModelDescriptor


class ModelPackError(ValueError):
    """Raised when a model pack is invalid, incomplete, or corrupted."""


@dataclass(frozen=True, slots=True)
class ModelInputContract:
    sample_rate_hz: int
    channels: int
    sample_format: str
    window_samples: int | None


@dataclass(frozen=True, slots=True)
class ModelArtifact:
    name: str
    path: Path
    kind: str
    sha256: str
    size_bytes: int


@dataclass(frozen=True, slots=True)
class ModelBenchmark:
    hardware: str
    os: str
    measured_at: str
    duration_seconds: float
    inference_count: int
    mean_latency_ms: float
    maximum_latency_ms: float


@dataclass(frozen=True, slots=True)
class VerifiedModelPack:
    pack_id: str
    version: str
    runtime: str
    license: str
    source: str
    locale: str
    supported_hardware: tuple[str, ...]
    input: ModelInputContract
    artifacts: tuple[ModelArtifact, ...]
    reference_benchmark: ModelBenchmark | None

    @property
    def model(self) -> ModelDescriptor:
        return ModelDescriptor(
            model_id=self.pack_id,
            version=self.version,
            runtime=self.runtime,
        )

    def artifact(self, name: str) -> ModelArtifact:
        matches = [artifact for artifact in self.artifacts if artifact.name == name]
        if len(matches) != 1:
            raise ModelPackError(f"model pack does not contain one artifact named {name!r}")
        return matches[0]


def load_verified_model_pack(manifest_path: Path) -> VerifiedModelPack:
    """Load a strict manifest and verify every declared local artifact."""

    try:
        raw = yaml.safe_load(manifest_path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise ModelPackError(f"cannot read model manifest {manifest_path}: {exc}") from exc
    except yaml.YAMLError as exc:
        raise ModelPackError(f"invalid model manifest YAML: {exc}") from exc

    root = _mapping(raw, "model pack")
    _keys(
        root,
        {
            "schema_version",
            "pack_id",
            "version",
            "runtime",
            "license",
            "source",
            "locale",
            "supported_hardware",
            "input",
            "artifacts",
            "reference_benchmark",
        },
        "model pack",
    )
    if _integer(root, "schema_version", "model pack") != 1:
        raise ModelPackError("unsupported model-pack schema_version")

    input_raw = _mapping(root["input"], "input")
    _keys(
        input_raw,
        {"sample_rate_hz", "channels", "sample_format", "window_samples"},
        "input",
    )
    input_contract = ModelInputContract(
        sample_rate_hz=_positive_integer(input_raw, "sample_rate_hz", "input"),
        channels=_positive_integer(input_raw, "channels", "input"),
        sample_format=_string(input_raw, "sample_format", "input"),
        window_samples=_optional_positive_integer(input_raw, "window_samples", "input"),
    )

    pack_root = manifest_path.resolve().parent
    artifacts_raw = root["artifacts"]
    if not isinstance(artifacts_raw, list) or not artifacts_raw:
        raise ModelPackError("artifacts must be a non-empty list")
    artifacts = tuple(
        _load_artifact(item, pack_root, index) for index, item in enumerate(artifacts_raw)
    )
    names = [artifact.name for artifact in artifacts]
    if len(names) != len(set(names)):
        raise ModelPackError("artifact names must be unique")

    hardware_raw = root["supported_hardware"]
    if not isinstance(hardware_raw, list) or not hardware_raw:
        raise ModelPackError("supported_hardware must be a non-empty list")
    supported_hardware = tuple(
        _non_empty_string(item, f"supported_hardware[{index}]")
        for index, item in enumerate(hardware_raw)
    )
    reference_benchmark = _load_optional_benchmark(root["reference_benchmark"])
    return VerifiedModelPack(
        pack_id=_string(root, "pack_id", "model pack"),
        version=_string(root, "version", "model pack"),
        runtime=_string(root, "runtime", "model pack"),
        license=_string(root, "license", "model pack"),
        source=_string(root, "source", "model pack"),
        locale=_string(root, "locale", "model pack"),
        supported_hardware=supported_hardware,
        input=input_contract,
        artifacts=artifacts,
        reference_benchmark=reference_benchmark,
    )


def _load_artifact(item: Any, pack_root: Path, index: int) -> ModelArtifact:
    path_name = f"artifacts[{index}]"
    raw = _mapping(item, path_name)
    required_keys = {"name", "path", "sha256", "size_bytes"}
    missing = required_keys - raw.keys()
    unknown = raw.keys() - required_keys - {"kind"}
    if missing:
        raise ModelPackError(
            f"{path_name} is missing keys: {', '.join(sorted(missing))}"
        )
    if unknown:
        raise ModelPackError(
            f"{path_name} contains unknown keys: {', '.join(sorted(unknown))}"
        )
    relative_path = Path(_string(raw, "path", path_name))
    artifact_path = (pack_root / relative_path).resolve()
    try:
        artifact_path.relative_to(pack_root)
    except ValueError as exc:
        raise ModelPackError(f"{path_name}.path must remain inside its model pack") from exc
    kind_value = raw.get("kind", "file")
    kind = _non_empty_string(kind_value, f"{path_name}.kind")
    if kind not in {"file", "directory"}:
        raise ModelPackError(f"{path_name}.kind must be file or directory")
    expected_size = _positive_integer(raw, "size_bytes", path_name)
    actual_size, actual_sha256 = _artifact_fingerprint(artifact_path, kind)
    if actual_size != expected_size:
        raise ModelPackError(
            f"model artifact size mismatch for {artifact_path.name}: "
            f"expected {expected_size}, got {actual_size}"
        )
    expected_sha256 = _string(raw, "sha256", path_name).lower()
    if len(expected_sha256) != 64 or any(
        character not in "0123456789abcdef" for character in expected_sha256
    ):
        raise ModelPackError(f"{path_name}.sha256 must be a lowercase SHA-256 digest")
    if actual_sha256 != expected_sha256:
        raise ModelPackError(f"model artifact checksum mismatch for {artifact_path.name}")
    return ModelArtifact(
        name=_string(raw, "name", path_name),
        path=artifact_path,
        kind=kind,
        sha256=expected_sha256,
        size_bytes=expected_size,
    )


def _artifact_fingerprint(path: Path, kind: str) -> tuple[int, str]:
    if kind == "file":
        if not path.is_file() or path.is_symlink():
            raise ModelPackError(f"model artifact file is missing: {path}")
        return path.stat().st_size, _sha256_file(path)
    if not path.is_dir() or path.is_symlink():
        raise ModelPackError(f"model artifact directory is missing: {path}")

    digest = hashlib.sha256()
    total_size = 0
    files: list[tuple[str, Path]] = []
    for child in path.rglob("*"):
        if child.is_symlink():
            raise ModelPackError(f"model artifact directory contains a symlink: {child}")
        if child.is_file():
            files.append((child.relative_to(path).as_posix(), child))
        elif not child.is_dir():
            raise ModelPackError(
                f"model artifact directory contains an unsupported entry: {child}"
            )
    if not files:
        raise ModelPackError(f"model artifact directory is empty: {path}")
    for relative_path, child in sorted(files):
        size = child.stat().st_size
        total_size += size
        digest.update(relative_path.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(size).encode("ascii"))
        digest.update(b"\0")
        _update_digest(digest, child)
    return total_size, digest.hexdigest()


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    _update_digest(digest, path)
    return digest.hexdigest()


def _update_digest(digest: Any, path: Path) -> None:
    with path.open("rb") as artifact:
        for chunk in iter(lambda: artifact.read(1024 * 1024), b""):
            digest.update(chunk)


def _mapping(value: Any, path: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise ModelPackError(f"{path} must be a mapping")
    return value


def _keys(value: Mapping[str, Any], expected: set[str], path: str) -> None:
    missing = expected - value.keys()
    unknown = value.keys() - expected
    if missing:
        raise ModelPackError(f"{path} is missing keys: {', '.join(sorted(missing))}")
    if unknown:
        raise ModelPackError(f"{path} contains unknown keys: {', '.join(sorted(unknown))}")


def _string(value: Mapping[str, Any], key: str, path: str) -> str:
    return _non_empty_string(value.get(key), f"{path}.{key}")


def _non_empty_string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ModelPackError(f"{path} must be a non-empty string")
    return value.strip()


def _integer(value: Mapping[str, Any], key: str, path: str) -> int:
    item = value.get(key)
    if type(item) is not int:
        raise ModelPackError(f"{path}.{key} must be an integer")
    return item


def _positive_integer(value: Mapping[str, Any], key: str, path: str) -> int:
    item = _integer(value, key, path)
    if item <= 0:
        raise ModelPackError(f"{path}.{key} must be positive")
    return item


def _optional_positive_integer(
    value: Mapping[str, Any],
    key: str,
    path: str,
) -> int | None:
    if value.get(key) is None:
        return None
    return _positive_integer(value, key, path)


def _load_optional_benchmark(value: Any) -> ModelBenchmark | None:
    if value is None:
        return None
    benchmark_raw = _mapping(value, "reference_benchmark")
    _keys(
        benchmark_raw,
        {
            "hardware",
            "os",
            "measured_at",
            "duration_seconds",
            "inference_count",
            "mean_latency_ms",
            "maximum_latency_ms",
        },
        "reference_benchmark",
    )
    return ModelBenchmark(
        hardware=_string(benchmark_raw, "hardware", "reference_benchmark"),
        os=_string(benchmark_raw, "os", "reference_benchmark"),
        measured_at=_string(benchmark_raw, "measured_at", "reference_benchmark"),
        duration_seconds=_positive_number(
            benchmark_raw,
            "duration_seconds",
            "reference_benchmark",
        ),
        inference_count=_positive_integer(
            benchmark_raw,
            "inference_count",
            "reference_benchmark",
        ),
        mean_latency_ms=_positive_number(
            benchmark_raw,
            "mean_latency_ms",
            "reference_benchmark",
        ),
        maximum_latency_ms=_positive_number(
            benchmark_raw,
            "maximum_latency_ms",
            "reference_benchmark",
        ),
    )


def _positive_number(value: Mapping[str, Any], key: str, path: str) -> float:
    item = value.get(key)
    if isinstance(item, bool) or not isinstance(item, (int, float)):
        raise ModelPackError(f"{path}.{key} must be a number")
    number = float(item)
    if number <= 0:
        raise ModelPackError(f"{path}.{key} must be positive")
    return number
