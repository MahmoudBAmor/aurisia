# ADR 0020: Arabic-first Audar refinement for formal speech

- Status: Accepted
- Date: 2026-09-02

## Context

Repeated Android field tests showed that MGB-2/Vosk plus multilingual Whisper
Small could preserve phrase boundaries yet still misrecognize central words in
sermons. Examples included common testimony and Qur'anic vocabulary. Tuning
silence, padding, or the cross-model agreement threshold cannot recover words
that neither decoder recognizes correctly.

The replacement must stay offline, run without a GPU on Android ARM64, keep
fast partial captions, and remain behind the existing `TranscriptionEngine`
port.

## Decision

Keep MGB-2/Vosk as the streaming primary and replace only the formal profile's
final recognizer with Audar-ASR-V1-Flash. Pin revision `54274d3`, use its
recommended Q8_0 decoder and mandatory BF16 audio projector, and decode
greedily with the Arabic system prompt. Run the model through
`llama_cpp_dart` 0.9.0-dev.12, pinned to llama.cpp b10182, with all model and
projector layers on CPU. WAV media is built in memory and never persisted.

The Audar adapter is the authoritative unscored final recognizer for the
formal profile. Vosk remains visible immediately and remains the fallback for
empty output or inference failure. Other profiles retain the conservative
agreement policy by default.

Bundle the exact AudarAI Open License v1.0, upstream NOTICE, and model card with
the checksum-pinned weights. Exclude the unused Omnilingual weights from the
Android APK.

## Consequences

- The screen, session, VAD, speaker attribution, and Vosk adapters do not know
  about GGUF or llama.cpp.
- Arabic final accuracy should improve materially, but must still be measured
  on the target phone and a representative MSA/classical-Arabic corpus.
- Fast Vosk partial text may be replaced after the stronger final pass; the
  event identity and speaker color remain stable.
- The formal pack is about 1.39 GB bundled and about 1.76 GB after MGB-2 is
  extracted. First profile preparation and first inference are correspondingly
  expensive.
- The selected Dart runtime is prerelease and llama.cpp audio support is still
  evolving. Both pins are explicit so the adapter can be upgraded or replaced
  without changing domain code.
- The current deliverable is Android ARM64. iOS requires a separately verified
  native runtime package even though the Dart interfaces are retained.
