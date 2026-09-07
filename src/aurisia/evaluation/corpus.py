"""Strict, versioned Tunisian ASR corpus manifests."""

from __future__ import annotations

import re
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml

_CASE_ID_PATTERN = re.compile(r"^[a-z0-9][a-z0-9_-]{0,63}$")


class CorpusError(ValueError):
    """Raised when an ASR corpus manifest is invalid."""


@dataclass(frozen=True, slots=True)
class CodeSwitchTerm:
    """Equivalent written forms accepted for one code-switched expression."""

    aliases: tuple[str, ...]

    def __post_init__(self) -> None:
        if not self.aliases or any(not alias.strip() for alias in self.aliases):
            raise ValueError("a code-switch term requires non-empty aliases")


@dataclass(frozen=True, slots=True)
class AsrEvaluationCase:
    case_id: str
    prompt_arabizi: str
    reference_arabic: str
    code_switch_terms: tuple[CodeSwitchTerm, ...]

    def __post_init__(self) -> None:
        if not _CASE_ID_PATTERN.fullmatch(self.case_id):
            raise ValueError(f"invalid ASR case id: {self.case_id!r}")
        if not self.prompt_arabizi.strip():
            raise ValueError("Arabizi prompt must not be empty")
        if not self.reference_arabic.strip():
            raise ValueError("Arabic reference must not be empty")


@dataclass(frozen=True, slots=True)
class AsrCorpus:
    corpus_id: str
    version: str
    locale: str
    display_mode: str
    cases: tuple[AsrEvaluationCase, ...]

    def __post_init__(self) -> None:
        if not _CASE_ID_PATTERN.fullmatch(self.corpus_id):
            raise ValueError(f"invalid ASR corpus id: {self.corpus_id!r}")
        if not self.version.strip():
            raise ValueError("corpus version must not be empty")
        if not self.locale.strip():
            raise ValueError("corpus locale must not be empty")
        if self.display_mode not in {"arabic", "arabizi"}:
            raise ValueError("display mode must be arabic or arabizi")
        if not self.cases:
            raise ValueError("ASR corpus must contain at least one case")
        identifiers = [case.case_id for case in self.cases]
        if len(identifiers) != len(set(identifiers)):
            raise ValueError("ASR corpus case ids must be unique")


def load_asr_corpus(path: Path) -> AsrCorpus:
    """Load a strict corpus without reading or creating any recording."""

    try:
        raw = yaml.safe_load(path.read_text(encoding="utf-8"))
    except OSError as exc:
        raise CorpusError(f"cannot read ASR corpus {path}: {exc}") from exc
    except yaml.YAMLError as exc:
        raise CorpusError(f"invalid ASR corpus YAML: {exc}") from exc

    root = _mapping(raw, "corpus")
    _keys(
        root,
        {
            "schema_version",
            "corpus_id",
            "version",
            "locale",
            "display_mode",
            "cases",
        },
        "corpus",
    )
    if _integer(root, "schema_version", "corpus") != 1:
        raise CorpusError("unsupported ASR corpus schema_version")

    raw_cases = root["cases"]
    if not isinstance(raw_cases, list) or not raw_cases:
        raise CorpusError("corpus.cases must be a non-empty list")
    try:
        cases = tuple(_load_case(item, index) for index, item in enumerate(raw_cases))
        return AsrCorpus(
            corpus_id=_string(root, "corpus_id", "corpus"),
            version=_string(root, "version", "corpus"),
            locale=_string(root, "locale", "corpus"),
            display_mode=_string(root, "display_mode", "corpus"),
            cases=cases,
        )
    except ValueError as exc:
        raise CorpusError(str(exc)) from exc


def _load_case(value: Any, index: int) -> AsrEvaluationCase:
    path = f"corpus.cases[{index}]"
    raw = _mapping(value, path)
    _keys(
        raw,
        {
            "id",
            "prompt_arabizi",
            "reference_arabic",
            "code_switch_terms",
        },
        path,
    )
    raw_terms = raw["code_switch_terms"]
    if not isinstance(raw_terms, list):
        raise CorpusError(f"{path}.code_switch_terms must be a list")
    terms = tuple(
        CodeSwitchTerm(_aliases(item, f"{path}.code_switch_terms[{term_index}]"))
        for term_index, item in enumerate(raw_terms)
    )
    return AsrEvaluationCase(
        case_id=_string(raw, "id", path),
        prompt_arabizi=_string(raw, "prompt_arabizi", path),
        reference_arabic=_string(raw, "reference_arabic", path),
        code_switch_terms=terms,
    )


def _aliases(value: Any, path: str) -> tuple[str, ...]:
    if not isinstance(value, list) or not value:
        raise CorpusError(f"{path} must be a non-empty list of aliases")
    aliases = tuple(
        _non_empty_string(alias, f"{path}[{index}]")
        for index, alias in enumerate(value)
    )
    if len(aliases) != len(set(alias.casefold() for alias in aliases)):
        raise CorpusError(f"{path} aliases must be unique")
    return aliases


def _mapping(value: Any, path: str) -> Mapping[str, Any]:
    if not isinstance(value, dict):
        raise CorpusError(f"{path} must be a mapping")
    return value


def _keys(value: Mapping[str, Any], expected: set[str], path: str) -> None:
    missing = expected - value.keys()
    unknown = value.keys() - expected
    if missing:
        raise CorpusError(f"{path} is missing keys: {', '.join(sorted(missing))}")
    if unknown:
        raise CorpusError(f"{path} contains unknown keys: {', '.join(sorted(unknown))}")


def _string(value: Mapping[str, Any], key: str, path: str) -> str:
    return _non_empty_string(value.get(key), f"{path}.{key}")


def _non_empty_string(value: Any, path: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise CorpusError(f"{path} must be a non-empty string")
    return value.strip()


def _integer(value: Mapping[str, Any], key: str, path: str) -> int:
    item = value.get(key)
    if type(item) is not int:
        raise CorpusError(f"{path}.{key} must be an integer")
    return item
