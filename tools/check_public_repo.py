"""Reject private, binary, generated, or secret material from public Git state."""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

MAX_SOURCE_FILE_BYTES = 20 * 1024 * 1024

_LOCAL_ONLY_NAMES = {
    ".ds_store",
    ".flutter-plugins-dependencies",
    "console.txt",
    "context.txt",
    "key.properties",
    "local.properties",
    "transcript.json",
}
_LOCAL_ONLY_DIRECTORIES = {
    ".dart_tool",
    ".git",
    ".hypothesis",
    ".mypy_cache",
    ".pytest_cache",
    ".ruff_cache",
    ".tox",
    ".venv",
    "build",
    "coverage",
    "dist",
    "recordings",
}
_BINARY_SUFFIXES = {
    ".7z",
    ".aab",
    ".apk",
    ".bin",
    ".dll",
    ".flac",
    ".gguf",
    ".gz",
    ".iml",
    ".jks",
    ".key",
    ".keystore",
    ".m4a",
    ".mp3",
    ".onnx",
    ".ort",
    ".p12",
    ".pem",
    ".pfx",
    ".pt",
    ".pth",
    ".safetensors",
    ".so",
    ".tar",
    ".tflite",
    ".wav",
    ".zip",
}
_TEXT_SUFFIXES = {
    "",
    ".cfg",
    ".dart",
    ".gradle",
    ".html",
    ".ini",
    ".java",
    ".json",
    ".kt",
    ".kts",
    ".md",
    ".ps1",
    ".py",
    ".qml",
    ".sh",
    ".toml",
    ".txt",
    ".xml",
    ".yaml",
    ".yml",
}
_SECRET_PATTERNS = {
    "private key material": re.compile(
        r"-----BEGIN (?:RSA |EC |DSA |OPENSSH )?PRIVATE KEY-----"
    ),
    "Google API key": re.compile(r"\bAIza[0-9A-Za-z_-]{35}\b"),
    "GitHub access token": re.compile(r"\bgh[pousr]_[0-9A-Za-z]{20,}\b"),
    "AWS access key": re.compile(r"\b(?:AKIA|ASIA)[A-Z0-9]{16}\b"),
}
_MODEL_METADATA_NAMES = {
    "license",
    "manifest.json",
    "manifest.yaml",
    "model_card.md",
    "notice",
    "readme.md",
}


class RepositoryAuditError(RuntimeError):
    """Raised when the Git index cannot be inspected."""


def tracked_paths(root: Path) -> tuple[Path, ...]:
    """Return every path Git would include, including already tracked ignores."""

    result = subprocess.run(
        ("git", "-C", str(root), "ls-files", "--cached", "-z"),
        check=False,
        capture_output=True,
    )
    if result.returncode != 0:
        detail = result.stderr.decode(errors="replace").strip()
        raise RepositoryAuditError(detail or "Git could not inspect the repository index.")
    return tuple(
        Path(raw.decode(errors="surrogateescape"))
        for raw in result.stdout.split(b"\0")
        if raw
    )


def inspect_file(
    root: Path,
    relative_path: Path,
    *,
    max_file_bytes: int = MAX_SOURCE_FILE_BYTES,
) -> tuple[str, ...]:
    """Return public-repository violations for one tracked path."""

    normalized_parts = tuple(part.lower() for part in relative_path.parts)
    name = relative_path.name.lower()
    issues: list[str] = []

    if name in _LOCAL_ONLY_NAMES:
        issues.append("local-only file")
    if any(part in _LOCAL_ONLY_DIRECTORIES for part in normalized_parts[:-1]):
        issues.append("generated or private directory")
    if name.startswith(".env") and name != ".env.example":
        issues.append("environment file")
    if any(name.endswith(suffix) for suffix in _BINARY_SUFFIXES):
        issues.append("binary, model, recording, build, or key artifact")
    in_model_tree = (
        normalized_parts[:1] in {("models",), ("runtimes",)}
        or normalized_parts[:3] == ("mobile", "assets", "model_packs")
    )
    is_model_metadata = (
        name in _MODEL_METADATA_NAMES
        or name.startswith("license.")
        or name.startswith("notice.")
        or (
            "tokenizer" in normalized_parts
            and relative_path.suffix.lower() in {".json", ".txt"}
        )
    )
    if in_model_tree and not is_model_metadata:
        issues.append("model or runtime tree contains non-metadata content")

    absolute_path = root / relative_path
    if not absolute_path.exists():
        return tuple(issues)
    if absolute_path.is_symlink():
        try:
            absolute_path.resolve(strict=True).relative_to(root.resolve(strict=True))
        except (FileNotFoundError, ValueError):
            issues.append("symbolic link escapes the repository")
        return tuple(issues)
    if not absolute_path.is_file():
        return tuple(issues)

    size = absolute_path.stat().st_size
    if size > max_file_bytes:
        issues.append(f"source file exceeds {max_file_bytes} bytes")

    if absolute_path.suffix.lower() in _TEXT_SUFFIXES and size <= max_file_bytes:
        content = absolute_path.read_text(encoding="utf-8", errors="replace")
        for label, pattern in _SECRET_PATTERNS.items():
            if pattern.search(content):
                issues.append(label)

    return tuple(issues)


def audit_repository(root: Path) -> tuple[str, ...]:
    """Audit all files currently tracked by Git."""

    violations: list[str] = []
    for relative_path in tracked_paths(root):
        for issue in inspect_file(root, relative_path):
            violations.append(f"{relative_path.as_posix()}: {issue}")
    return tuple(violations)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Fail when tracked Git files are unsafe for Aurisia's public repository."
    )
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="repository root (defaults to the parent of tools)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    root = args.root.resolve()
    try:
        paths = tracked_paths(root)
        violations = tuple(
            f"{relative_path.as_posix()}: {issue}"
            for relative_path in paths
            for issue in inspect_file(root, relative_path)
        )
    except RepositoryAuditError as exc:
        print(f"public repository audit could not run: {exc}", file=sys.stderr)
        return 2

    if violations:
        print("public repository audit failed:", file=sys.stderr)
        for violation in violations:
            print(f"  - {violation}", file=sys.stderr)
        return 1

    print(f"public repository audit passed: {len(paths)} tracked files checked")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
