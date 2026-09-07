# ADR 0026: Dedicated offline Quran-recitation profile

- Status: Rejected after Android field evaluation
- Date: 2026-09-02

## Context

Android field testing showed that the formal-Arabic sermon profile performs
poorly on Surat Al-Insan. Quranic recitation has prolonged vowels, tajwid, and
different pause patterns from conversational or broadcast Arabic. Further
tuning the shared sermon policy would risk regressions without addressing the
acoustic-domain mismatch.

Tarteel AI publishes `whisper-base-ar-quran` under Apache-2.0. Synthesium
publishes an INT8 ONNX export for sherpa-onnx at immutable revision
`a0e6feae0693a70365cd7d9d777f85dbd9ec417d`. The export uses the same offline
runtime and `TranscriptionEngine` port already present in Aurisia. Its encoder,
decoder, and tokens total 160,580,569 bytes.

## Decision

Add a user-selectable `quranRecitation` profile. Keep MGB-2/Vosk as its
low-latency streaming recognizer and use the Quran-fine-tuned Whisper Base INT8
pack as its final recognizer.

Append 500 ms of silence only at the Quran decoder boundary because the export
documents that tightly cut segments may otherwise lose the final word. The
padder is a replaceable `SpeechTurnPreprocessor`; captured timestamps, speaker
embeddings, and streaming ASR continue to use original PCM.

The specialized unscored result must still pass normalized similarity,
token-retention, and maximum-growth gates. It must not turn a very short
fragment into a guessed complete verse.

## Consequences

- Quran performance can improve independently of Tunisian and sermon speech.
- The APK and installed-model footprint each increase by about 161 MB.
- The dedicated final result arrives after immediate provisional Vosk text.
- Model identity, immutable revision, file sizes, and SHA-256 hashes remain in
  the standard model-pack contract.
- Real-device evaluation on multiple reciters and surahs remains required; the
  upstream export's quality claim is not treated as an Aurisia benchmark.

## Field result

The first real-device comparison rejected this decision. On the reference
SM-S928B, the Quran Whisper candidate returned unrelated or malformed verses
for every captured turn. The MGB-2 baseline also disagreed strongly, with
normalized similarities between 0.00 and 0.30. A 24.6-second turn produced a
long completion unrelated to the baseline and made the final-ASR backlog
visible to the user.

The profile and model are therefore removed from the distributable APK. The
generic Whisper adapter and preprocessor remain available for future model
evaluation, but no Quran-specific mode will be exposed again without a
representative device corpus and an acceptance threshold.
