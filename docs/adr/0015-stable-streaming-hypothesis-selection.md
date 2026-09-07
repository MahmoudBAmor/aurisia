# ADR 0015: Stable streaming hypothesis selection

- Status: Superseded by ADR 0017
- Date: 2026-09-02

## Context

Android field testing exposed a harmful streaming failure: Vosk could display
the right Tunisian partial while the person was speaking, then replace it with
a divergent final hypothesis after the pause. The session previously trusted
every non-empty final unconditionally. The optional formal-Arabic refiner had
the same authority over a good streaming result.

Users also noticed avoidable post-speech delay. Endpoint silence must be short
enough for live accessibility, without splitting words and natural formal-speech
pauses.

## Decision

Introduce a model-neutral `StreamingHypothesisPolicy` in the application layer.
Track repeated partial hypotheses for each speech turn. Accept the decoder
final when it matches or extends the stable partial, crosses a configurable
similarity threshold, or has a material confidence advantage. Otherwise,
finalize the stable partial. Apply an independent agreement and baseline-
confidence-advantage gate to optional second-pass refinement. A missing score
is not evidence that a divergent refinement is better.

Keep thresholds in `LiveTranscriptionProfile`, not in Vosk, Whisper, or the UI.
Use 220 ms endpoint silence for Tunisian conversation and 320 ms for the
formal-Arabic profile. Log the selection reason, similarity, and latency without
logging transcript text or audio.

## Consequences

- A fleeting partial remains provisional; only repeated text can overrule a
  decoder final.
- A weak, unrelated final no longer erases a stable Tunisian phrase.
- A formal-Arabic result cannot be replaced by a divergent, unscored second
  model; the current Whisper adapter is therefore limited to close corrections.
- Post-speech endpoint delay drops by 80 ms for Tunisian and 130 ms for formal
  Arabic relative to the previous mobile profiles.
- The policy mitigates visible regressions; it does not improve the acoustic
  model's vocabulary. Representative consented Tunisian recordings and
  correction labels remain necessary for genuine model-quality gains.
