# ADR 0018: Formal-speech sustained-phonation conditioning

- Status: Accepted experimentally
- Date: 2026-09-02

## Context

Expressive speech can sustain a vowel for much longer than ordinary
conversation. Mobile testing reports recognition errors around these spans. A
phrase-replacement table would hide model errors, risk changing unrelated
speech, and would not generalize to other words or speaking styles.

The original waveform remains important for speaker attribution, and the live
Vosk result must remain responsive. The existing formal-Arabic final gate can
protect a good baseline from an unsupported second-pass rewrite.

## Decision

Add a model-neutral `SpeechTurnPreprocessor` port and a transcription-engine
decorator. Enable a `SustainedPhonationCompressor` only before a final
recognizer whose evaluation shows that it benefits from the transform.

Analyze non-overlapping 20 ms mono frames using RMS energy, zero-crossing rate,
and normalized waveform slope. Treat only stable voiced runs of at least
900 ms as sustained phonation. Preserve their onset and ending, reduce the
complete span to approximately 560 ms, and crossfade the join. Do not transform
short vowels, rapidly changing voiced audio, Tunisian conversation, streaming
Vosk input, or speaker-embedding input.

Continue applying cross-model agreement after recognition. A divergent result
from transformed audio cannot replace the baseline merely because
preprocessing was applied. Record duration metrics without recording audio or
transcript text.

## Consequences

- Atypical vowel duration is brought closer to general ASR training conditions
  while remaining audibly long in the signal presented to the final model.
- Removing repetitive audio can reduce final-pass inference time for affected
  turns.
- The transform is linear-time, local, offline, model-replaceable, and covered
  by synthetic signal tests.
- Synthetic tests establish DSP boundaries, not recognition quality. The
  threshold and benefit must be validated using consented recordings with
  different pitches, microphones, rooms, and expressive speaking styles.
