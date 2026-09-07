# ADR 0023: Formal-Arabic boundary retention

- Status: Rejected after same-audio field comparison
- Date: 2026-09-02

## Context

Field comparison against a time-aligned khutba transcript showed that overall
formal-Arabic recognition improved after language-constrained, guarded Qwen
refinement. Remaining errors include both ordinary substitutions in the middle
of a turn and occasional missing words at a turn boundary. Only the latter can
be addressed safely in VAD composition; inferred text completion would risk
reintroducing hallucinations.

## Decision

For the formal-Arabic sermon profile only, lower the Silero speech threshold
from 0.5 to 0.4, require 800 ms of silence before finalization, and provide
650 ms of retained real PCM on each side of the VAD segment. Keep the Tunisian
conversation values unchanged. Preserve the guarded Vosk/Qwen arbitration and
do not reconstruct missing words from a language model.

## Consequences

- Weak initial and final consonants have more chance to remain in the final-ASR
  waveform, and short rhetorical pauses are less likely to create boundaries.
- Formal finalization gains approximately 150 ms of endpoint latency; streaming
  partial text remains immediate.
- More surrounding silence is processed by Qwen, with no additional recording,
  cloud service, or persistent audio.
- Interior recognition errors remain model/evaluation concerns and are not
  mislabeled as VAD clipping.

## Field outcome

Repeating the same khutba after installing this change produced a worse
transcript. The threshold, endpoint silence, and padding values were therefore
restored to their pre-experiment settings. Further boundary changes require a
captured Vosk/Qwen comparison rather than inference from the displayed text.
