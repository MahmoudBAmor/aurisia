# ADR 0021: Shared Qwen3 multilingual refinement

- Status: Superseded by ADR 0022
- Date: 2026-09-02

## Context

Android field testing found two related limitations in the packaged ASR
composition. Audar-ASR-V1-Flash changed several nearly correct formal-Arabic
results into worse sentences on formal-Arabic audio. The Tunisian LiNTO/Vosk decoder
also omitted or phonetically arabized embedded French and medicine terms such
as `pharmacie` and `Panadol`. Display substitutions cannot reconstruct a word
that is absent from the recognizer output.

Qwen3-ASR 0.6B officially supports both Arabic and French, offline inference,
code-switching, and decoder hotwords. Sherpa-onnx 1.13.6 exposes its INT8 model
through the existing Flutter/Android CPU runtime, so it does not require a new
platform channel or a dependency from presentation code.

## Decision

Keep the profile-specific Vosk models as low-latency streaming recognizers and
use one checksum-pinned Qwen3-ASR 0.6B INT8 pack as the final recognizer for
both profiles. The final recognizer remains behind `TranscriptionEngine` and
runs in a worker isolate. Completed turns are refined asynchronously, so model
inference never pauses microphone consumption or streaming partial text.

Provide short, profile-owned hotword lists to the Qwen adapter. The Tunisian
list contains common French loans and medicine terms; the formal list contains
general standard-Arabic terms. Hotwords are comma-separated decoder context,
not post-recognition text replacements. The Arabic display normalizer remains
a separate, conservative final formatting step.

Do not apply the experimental sustained-phonation waveform compressor to
Qwen3-ASR. The model explicitly supports singing and long vocal patterns, and
altering formal-Arabic audio before a new field evaluation would confound the model
comparison. The preprocessor remains replaceable for older final adapters.

## Consequences

- One approximately 984 MB bundled model serves Tunisian Arabic, French
  code-switching, and formal Arabic without duplicating weights per profile.
- Fast Vosk partials remain visible while Qwen produces an authoritative final
  update. Empty output or an engine failure preserves the Vosk result.
- The first launch copies and verifies a large model pack; later launches reuse
  the private installed copy and remain fully offline.
- Generic hotwords should improve named terms but cannot prove Tunisian or
  formal-Arabic accuracy. Representative consented audio and corrected references are
  still required for WER/CER and device-latency acceptance gates.
- Audar, Whisper, and Omnilingual adapters remain replaceable comparison
  implementations, but their weights are excluded from the packaged APK.
