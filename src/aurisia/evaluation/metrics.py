"""Dependency-free text metrics for Arabic and code-switched ASR."""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass

from .corpus import CodeSwitchTerm


@dataclass(frozen=True, slots=True)
class ErrorRate:
    edit_distance: int
    reference_units: int

    @property
    def rate(self) -> float:
        if self.reference_units == 0:
            return 0.0 if self.edit_distance == 0 else 1.0
        return self.edit_distance / self.reference_units


def word_error(reference: str, hypothesis: str) -> ErrorRate:
    reference_words = normalized_words(reference)
    hypothesis_words = normalized_words(hypothesis)
    return ErrorRate(
        edit_distance=_levenshtein(reference_words, hypothesis_words),
        reference_units=len(reference_words),
    )


def character_error(reference: str, hypothesis: str) -> ErrorRate:
    reference_characters = tuple("".join(normalized_words(reference)))
    hypothesis_characters = tuple("".join(normalized_words(hypothesis)))
    return ErrorRate(
        edit_distance=_levenshtein(reference_characters, hypothesis_characters),
        reference_units=len(reference_characters),
    )


def retained_code_switch_terms(
    hypothesis: str,
    terms: tuple[CodeSwitchTerm, ...],
) -> int:
    hypothesis_words = normalized_words(hypothesis)
    return sum(
        any(_contains_phrase(hypothesis_words, normalized_words(alias)) for alias in term.aliases)
        for term in terms
    )


def normalized_words(text: str) -> tuple[str, ...]:
    decomposed = unicodedata.normalize("NFKD", text.casefold())
    normalized: list[str] = []
    for character in decomposed:
        category = unicodedata.category(character)
        if category.startswith("M") or character == "\u0640":
            continue
        if category.startswith(("P", "S", "Z")):
            normalized.append(" ")
            continue
        normalized.append(character)
    return tuple("".join(normalized).split())


def _contains_phrase(haystack: tuple[str, ...], needle: tuple[str, ...]) -> bool:
    if not needle or len(needle) > len(haystack):
        return False
    width = len(needle)
    return any(
        _phrase_matches(haystack[index : index + width], needle)
        for index in range(len(haystack) - width + 1)
    )


def _phrase_matches(actual: tuple[str, ...], expected: tuple[str, ...]) -> bool:
    return all(
        actual_word == expected_word
        or (
            _is_arabic(expected_word)
            and actual_word.endswith(expected_word)
            and actual_word[: -len(expected_word)]
            in {"و", "ف", "ب", "ل", "لل", "ال", "وال", "بال", "كال"}
        )
        for actual_word, expected_word in zip(actual, expected, strict=True)
    )


def _is_arabic(value: str) -> bool:
    return any("\u0600" <= character <= "\u06ff" for character in value)


def _levenshtein(reference: tuple[str, ...], hypothesis: tuple[str, ...]) -> int:
    if len(reference) < len(hypothesis):
        reference, hypothesis = hypothesis, reference
    previous = list(range(len(hypothesis) + 1))
    for row, reference_unit in enumerate(reference, start=1):
        current = [row]
        for column, hypothesis_unit in enumerate(hypothesis, start=1):
            current.append(
                min(
                    current[column - 1] + 1,
                    previous[column] + 1,
                    previous[column - 1] + (reference_unit != hypothesis_unit),
                )
            )
        previous = current
    return previous[-1]
