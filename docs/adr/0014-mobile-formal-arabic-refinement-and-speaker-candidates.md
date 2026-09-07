# ADR 0014: Mobile formal-Arabic refinement and persistent speaker candidates

- Status: Accepted
- Date: 2026-09-01

## Context

Field testing found two independent failures. The MGB-2/Vosk profile remained
responsive but struggled with formal and classical Arabic outside its broadcast
domain. Speaker attribution became too conservative after false-color
hardening: a new speaker had to appear on consecutive turns, so A-B-A-B speech
could leave every turn assigned to A.

Formal-Arabic accuracy must improve without taking low-latency partial text away
from the user. Speaker changes still need protection from one noisy embedding.
All model choices must remain behind existing application ports.

## Decision

Keep MGB-2/Vosk as the formal profile's streaming primary ASR. Add the pinned
multilingual Whisper Small INT8 encoder, decoder, and tokens as an optional
turn-based final `TranscriptionEngine`. Start final recognition and speaker
embedding work together after VAD completes a turn. Publish Vosk immediately,
then upsert the same event with the non-empty Whisper result. A failed or empty
refinement preserves the streaming result.

Replace the single consecutive speaker candidate with a bounded candidate
pool. Candidates persist across known-speaker turns, expire after eight turns,
and are confirmed after two mutually similar observations. Raise the known
speaker threshold and keep a separate, stricter candidate-coherence threshold.

## Consequences

- Tunisian ASR behavior and latency are unchanged.
- Formal text remains visible immediately and may improve once final refinement
  completes; the UI does not depend on either runtime.
- The formal pack grows by about 375 MB and needs enough RAM for Vosk and
  Whisper to remain loaded together.
- The second observation of a new voice receives the new color. The first one
  intentionally keeps the previous color rather than trusting one sample.
- Session-local clustering still cannot separate simultaneous overlapping
  voices or assign real-world identities.
