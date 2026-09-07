# ADR 0024: Compile-time opt-in ASR field diagnostics

- Status: Accepted for development builds only
- Date: 2026-09-02

## Context

The visible final transcript is insufficient to diagnose whether an error came
from the streaming Vosk baseline, the Qwen refinement, VAD boundaries, or the
model-neutral selection policy. Release-mode `developer.log` diagnostics do
not expose the candidate texts through Android logcat, and repeated parameter
tuning without those candidates produced a regression.

## Decision

Add a compile-time `AURISIA_ASR_DIAGNOSTICS` flag. When explicitly enabled, a
completed turn prints one JSON record containing its audio duration, Vosk
baseline, Qwen refinement, selected result, models, similarity, and selection
reason. Do not record waveform samples and do not persist the JSON. Compile the
branch out of normal builds.

## Consequences

- A connected development phone can provide direct evidence for model and
  boundary decisions after a consented field test.
- Diagnostic APKs expose spoken text to Android's temporary log buffer and
  must not be distributed to end users.
- The ASR and UI interfaces remain unchanged; diagnostics observe composition
  decisions without becoming a model dependency.
