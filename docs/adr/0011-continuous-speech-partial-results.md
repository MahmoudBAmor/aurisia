# ADR 0011: Continuous-speech partial results

- Status: Accepted
- Date: 2026-07-30

## Context

The first streaming implementation amortized Vosk decoding while audio
arrived, but emitted a `TranscriptEvent` only after VAD reported
`SPEECH_END`. A user speaking continuously therefore saw no HUD text even
though the decoder was processing audio. An uninterrupted or falsely
continuous VAD interval could also grow decoder state without a bound.

Live measurements across 17 utterances showed 158 ms median and 193 ms mean
finalization, with three outliers between 385 and 547 ms. Shortening the VAD
silence window would not solve continuous speech and would make natural-pause
segmentation less reliable.

## Decision

Add an optional `PreviewingSpeechSession` capability owned by the speech
service. A capable adapter may return a non-final `SpeechHypothesis` without
changing the complete-segment or streaming engine contracts.

Poll changed preview text at a configurable 750 ms interval. Publish preview
and final transcripts under one stable event identity so downstream projection
updates the same HUD card and direction. Vosk combines already completed
internal endpoints with its current partial result.

Independently cap every active speech session at 30 seconds. At the bound,
finalize the segment and begin another session on the next active frame. This
keeps memory bounded and gives complete-segment engines a generic fallback.

## Consequences

Continuous speech becomes visible before the speaker pauses, while final
transcripts and existing adapters preserve their contracts. Preview extraction
is included in the model-neutral inference measurement.

Partial text is unstable by definition and may revise words as more audio
arrives. The current HUD replaces its text rather than accumulating cards.
Long-session rollover can split a word at the boundary; 30 seconds makes that
rare and bounds the failure mode. A future renderer may visually distinguish
non-final text without changing recognition.
