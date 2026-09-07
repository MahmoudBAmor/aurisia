# ADR 0027: Full Tunisian Vosk and bounded final refinement

- Status: Accepted
- Date: 2026-09-02

## Context

Transcript diagnostics from the reference SM-S928B showed two independent
problems. Qwen3-ASR frequently degraded the Tunisian Vosk result, including
French medicine code-switches, while its serialized second-pass queue made
latency grow during continuous use. The packaged Tunisian archive was exactly
the simplified Android graph published with `Sali7a8603/Tunisian_STT`.

The same source publishes a full Kaldi/Vosk graph intended as its accuracy
tier. Its pinned 541,801,652-byte archive expands to a 1,459,583,859-byte Vosk
tree and uses the existing streaming adapter without a runtime change.

## Decision

Use the checksum-pinned full Tunisian graph as the conversation profile's only
ASR engine. Do not load Qwen for Tunisian conversation. Keep French and known
medicine rendering in a conservative, replaceable display normalizer.

Keep MGB-2 streaming plus guarded Qwen refinement for formal Arabic. Split
speaker attribution from final-ASR scheduling. Permit one active final
inference and retain only the newest waiting turn; superseded turns remain on
their immediate Vosk result. Do not publish a final refinement after its
freshness deadline.

Remove the rejected specialist profile and its model pack from the APK and
selector. Retain generic ASR and preprocessing adapters for future experiments.

## Consequences

- Tunisian decoding uses a graph roughly five times larger after extraction;
  first installation and model initialization take longer and use more RAM.
- Tunisian live transcription avoids all Qwen CPU, RAM, correction, and queue
  latency.
- Formal Arabic keeps the accuracy benefit observed from Qwen without an
  unbounded backlog or delayed speaker clustering.
- The full Tunisian model still requires a representative field comparison;
  its upstream benchmark is evidence for testing, not an Aurisia guarantee.
- A larger 1.7B Qwen export is not adopted: the official sherpa-onnx request is
  still open, the available export is third-party, and its approximately 2 GB
  decoder would make CPU latency worse on the reference phone.
