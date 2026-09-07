from __future__ import annotations

import hashlib
import tempfile
import unittest
from pathlib import Path

from aurisia.model_packs import ModelPackError, load_verified_model_pack


class ModelPackTests(unittest.TestCase):
    def test_loads_and_verifies_a_strict_model_pack(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "model.onnx"
            artifact.write_bytes(b"verified model")
            digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
            manifest = root / "manifest.yaml"
            manifest.write_text(
                _manifest(digest=digest, size=artifact.stat().st_size),
                encoding="utf-8",
            )

            pack = load_verified_model_pack(manifest)

        self.assertEqual(pack.pack_id, "test-vad")
        self.assertEqual(pack.input.sample_rate_hz, 16_000)
        self.assertEqual(pack.artifact("vad").sha256, digest)
        self.assertEqual(pack.model.runtime, "onnxruntime")
        self.assertIsNotNone(pack.reference_benchmark)
        assert pack.reference_benchmark is not None
        self.assertEqual(pack.reference_benchmark.hardware, "Test CPU")

    def test_allows_an_unbenchmarked_candidate_with_variable_length_input(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "model.onnx"
            artifact.write_bytes(b"candidate model")
            digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
            manifest = root / "manifest.yaml"
            manifest.write_text(
                _manifest(
                    digest=digest,
                    size=artifact.stat().st_size,
                    window_samples="null",
                    reference_benchmark="null",
                ),
                encoding="utf-8",
            )

            pack = load_verified_model_pack(manifest)

        self.assertIsNone(pack.input.window_samples)
        self.assertIsNone(pack.reference_benchmark)

    def test_rejects_a_corrupted_artifact(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            artifact = root / "model.onnx"
            artifact.write_bytes(b"corrupted")
            manifest = root / "manifest.yaml"
            manifest.write_text(
                _manifest(digest="0" * 64, size=artifact.stat().st_size),
                encoding="utf-8",
            )

            with self.assertRaisesRegex(ModelPackError, "checksum mismatch"):
                load_verified_model_pack(manifest)

    def test_verifies_a_directory_artifact_as_one_immutable_tree(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            model = root / "model"
            (model / "graph").mkdir(parents=True)
            (model / "am").mkdir()
            (model / "graph" / "words.txt").write_bytes(b"one two")
            (model / "am" / "final.mdl").write_bytes(b"model")
            size, digest = _tree_fingerprint(model)
            manifest = root / "manifest.yaml"
            manifest.write_text(
                _manifest(
                    digest=digest,
                    size=size,
                    artifact_path="model",
                    artifact_kind="directory",
                ),
                encoding="utf-8",
            )

            pack = load_verified_model_pack(manifest)

            self.assertEqual(pack.artifact("vad").kind, "directory")
            (model / "graph" / "words.txt").write_bytes(b"changed")
            with self.assertRaisesRegex(ModelPackError, "size mismatch|checksum mismatch"):
                load_verified_model_pack(manifest)


def _manifest(
    *,
    digest: str,
    size: int,
    window_samples: str = "512",
    reference_benchmark: str | None = None,
    artifact_path: str = "model.onnx",
    artifact_kind: str | None = None,
) -> str:
    benchmark = reference_benchmark or """\
hardware: Test CPU
  os: Test OS
  measured_at: "2026-07-29"
  duration_seconds: 1.0
  inference_count: 10
  mean_latency_ms: 0.5
  maximum_latency_ms: 1.0"""
    kind = "" if artifact_kind is None else f"\n    kind: {artifact_kind}"
    return f"""\
schema_version: 1
pack_id: test-vad
version: "1"
runtime: onnxruntime
license: MIT
source: https://example.invalid/model
locale: multilingual
supported_hardware:
  - cpu-x86_64
input:
  sample_rate_hz: 16000
  channels: 1
  sample_format: pcm_f32
  window_samples: {window_samples}
reference_benchmark:
  {benchmark}
artifacts:
  - name: vad
    path: {artifact_path}{kind}
    sha256: "{digest}"
    size_bytes: {size}
"""


def _tree_fingerprint(root: Path) -> tuple[int, str]:
    digest = hashlib.sha256()
    total = 0
    for path in sorted(item for item in root.rglob("*") if item.is_file()):
        relative = path.relative_to(root).as_posix()
        size = path.stat().st_size
        total += size
        digest.update(relative.encode("utf-8"))
        digest.update(b"\0")
        digest.update(str(size).encode("ascii"))
        digest.update(b"\0")
        digest.update(path.read_bytes())
    return total, digest.hexdigest()


if __name__ == "__main__":
    unittest.main()
