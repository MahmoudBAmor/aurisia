# ADR 0003: Tunisian Arabic display

- Status: Accepted
- Date: 2026-07-29

## Context

Tunisian speech frequently code-switches with French and English, and its
orthography is not fully standardized. The selected user-facing mode is Arabic
script.

## Decision

Use locale `aeb-TN`, right-to-left layout, and European digits by default.
Preserve the raw ASR transcript and create a separate display transcript.
Transliterate only curated terms from the installed language pack. Unknown
Latin tokens remain visible rather than being guessed.

## Consequences

Display preferences can change without retraining ASR, evaluation retains the
original evidence, and mixed-script edge cases remain recoverable.
