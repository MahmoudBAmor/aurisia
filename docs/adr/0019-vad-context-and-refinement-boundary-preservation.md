# ADR 0019: VAD context and refinement-boundary preservation

- Status: Accepted
- Date: 2026-09-02

## Context

Android formal-Arabic testing repeatedly omitted complete opening or closing
words. The affected recordings included explanatory prose, long vowels, and
rhetorical pauses, showing that the problem was at the audio boundary rather
than in one vocabulary domain.

The native VAD returns a tightly delimited speech array for second-pass ASR and
speaker attribution. Its endpoint is emitted only after trailing silence has
already been captured, but the application discarded that available raw PCM.
Streaming Vosk separately receives continuous frames. A close, unscored
Whisper result could also pass the overall-similarity gate after deleting a
short prefix or suffix from the Vosk baseline.

## Decision

Decorate the VAD with a model-neutral `ContextPaddingSpeechSegmenter`. Retain a
bounded chronological history of the original mono PCM and expand every
completed turn using already-captured context: 250 ms on both sides for
Tunisian conversation and 350 ms on both sides for formal Arabic. Do not add
an endpoint delay. Size history to the profile's maximum turn plus five
seconds, and fall back to the original segment if a complete requested range
is unavailable.

Extend `StreamingHypothesisPolicy` with refinement-boundary preservation. An
unscored second-pass result must retain sufficiently similar normalized first
and last two-token regions before direct or alternative agreement can replace
the baseline. Explicitly scored refinements retain the existing high-
confidence escape hatch. Keep thresholds in the application policy rather
than Vosk, Whisper, VAD, or presentation.

## Consequences

- Weak onset and release phonemes become available to final ASR without extra
  wall-clock waiting.
- Context is real microphone audio, not fabricated silence or phrase-specific
  text correction.
- Up to roughly 25 seconds of mono 16 kHz float PCM is retained in memory for
  the formal-Arabic profile, then discarded incrementally.
- Speaker embeddings receive a small amount of surrounding silence. Padding
  remains below the profile's required inter-turn silence, limiting adjacent-
  speaker contamination.
- If the primary streaming model itself never recognizes a clipped word, the
  refinement boundary guard cannot invent it; field recordings remain needed
  to measure whether context padding recovers it.
