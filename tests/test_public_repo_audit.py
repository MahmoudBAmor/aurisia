from __future__ import annotations

from pathlib import Path

from tools.check_public_repo import inspect_file


def test_accepts_ordinary_source_text(tmp_path: Path) -> None:
    source = tmp_path / "README.md"
    source.write_text("# Public source\n", encoding="utf-8")

    assert inspect_file(tmp_path, Path("README.md")) == ()


def test_rejects_private_evaluation_material(tmp_path: Path) -> None:
    transcript = tmp_path / "recordings" / "field.txt"
    transcript.parent.mkdir()
    transcript.write_text("private transcript", encoding="utf-8")

    assert "generated or private directory" in inspect_file(
        tmp_path, Path("recordings/field.txt")
    )


def test_rejects_model_and_signing_artifacts(tmp_path: Path) -> None:
    model = tmp_path / "model.onnx"
    model.write_bytes(b"model")
    key = tmp_path / "upload.jks"
    key.write_bytes(b"key")

    assert inspect_file(tmp_path, Path("model.onnx")) == (
        "binary, model, recording, build, or key artifact",
    )
    assert inspect_file(tmp_path, Path("upload.jks")) == (
        "binary, model, recording, build, or key artifact",
    )


def test_rejects_large_source_and_embedded_secret(tmp_path: Path) -> None:
    source = tmp_path / "settings.py"
    token = "ghp_" + "abcdefghijklmnopqrstuvwxyz123456"
    source.write_text(
        f"token = '{token}'\n",
        encoding="utf-8",
    )

    issues = inspect_file(tmp_path, Path("settings.py"), max_file_bytes=8)

    assert "source file exceeds 8 bytes" in issues

    secret_issues = inspect_file(tmp_path, Path("settings.py"))
    assert "GitHub access token" in secret_issues
