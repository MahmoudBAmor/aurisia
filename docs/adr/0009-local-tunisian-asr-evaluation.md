# ADR 0009: Local Tunisian ASR evaluation corpus

- Status: Accepted
- Date: 2026-07-30

## Context

Screenshots from ad hoc phrases established that the generic Arabic Moonshine
candidate was fast enough to investigate but often substituted Tunisian words
and French loanwords. Display transliteration cannot repair acoustic errors,
and selecting another model from isolated screenshots would not be repeatable.
Normal product operation must continue to retain no audio.

## Decision

Add an explicit evaluation composition outside the live product path. Version
strict text-only corpus manifests containing stable case ids, Arabizi prompts,
Arabic display references, and alternative spellings of code-switched terms.
Store private recordings only under the ignored local recording root.

Require a visible privacy notice and the exact confirmation word `RECORD`
before opening the microphone. Capture one VAD-delimited utterance per case,
including the configured pre-roll, and atomically store canonical 16 kHz mono
PCM. Resume by skipping existing files; replacement requires an explicit flag.

Replay recordings through `SpeechRecognitionService` and the configured
`SpeechEngine`. Report raw and display transcripts, normalized WER/CER,
code-switch retention, recognition latency, and RTF. Refuse to overwrite an
existing JSON report.

## Consequences

Moonshine, Whisper, and future Tunisian adapters can be compared against the
same local evidence without adding model-specific evaluation code. Raw output
remains distinguishable from display normalization, so presentation rules
cannot conceal model errors.

Recordings contain sensitive speech and are intentionally not portable source
artifacts. The starter corpus is small and its Arabic references are
provisional; it measures regression on observed phrases, not general Tunisian
accuracy. A representative, reviewed corpus is still required before a model
can be accepted for production.
