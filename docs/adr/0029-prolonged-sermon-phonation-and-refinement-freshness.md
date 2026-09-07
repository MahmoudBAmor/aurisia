# ADR 0029: Prolonged sermon phonation and refinement freshness

- Status: Accepted
- Date: 2026-09-06

## Context

A repeated Android field replay included an imam sustaining words in the
shahada for about three seconds. The streaming Vosk result contained a mixed
Arabic/Latin corrupt token and unrelated words. Qwen recovered the intended
sentence, but its result completed 4.1 seconds after the turn boundary and was
discarded by the former four-second freshness limit. The user therefore saw
the corrupt provisional card even after stopping the session.

ADR 0021 deliberately bypassed the existing sustained-phonation conditioner
for Qwen. The diagnostic confirms that decision: with the original waveform,
Qwen recovered the complete prolonged shahada accurately.

## Decision

Continue sending the original sermon waveform to Qwen. Keep the replaceable
`SustainedPhonationCompressor` available only for final adapters that need it;
Vosk streaming and speaker embeddings also continue to consume the original
waveform.

Make final-result freshness profile-owned. Retain four seconds for ordinary
conversation and allow eight seconds for formal sermons, so an already useful
correction is not discarded just beyond the generic limit.

Let the formal display normalizer reject a provisional hypothesis containing a
token that combines Arabic and Latin characters, or the Unicode replacement
character. The surrounding text is unreliable in the observed failure, so it
is safer to wait for Qwen than to display a partially cleaned sentence. Pure
Arabic and pure Latin tokens remain untouched. The Tunisian normalizer does not
enable this filter because legitimate code-switching is part of that profile.

## Consequences

- A provisional formal result may still appear immediately, but a completed
  Qwen correction can replace it for up to eight seconds.
- Qwen keeps the complete prolonged vowel that succeeded in this field test;
  identity, recording boundaries, and the streaming path are unchanged.
- Stopping a recording can take slightly longer while an accepted formal
  correction completes.
- The diagnostic build continues to report final-ASR timing without storing
  audio, allowing the freshness limit to be validated from field evidence.
