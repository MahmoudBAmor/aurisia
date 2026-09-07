# ADR 0030: Formal-Arabic leading context

- Status: Accepted pending field validation
- Date: 2026-09-06

## Context

Phone diagnostics for the formal-Arabic profile captured turns in which a weak
initial `في` was absent from both the streaming Vosk hypothesis and the Qwen
refinement. In one case Qwen retained only the final `ي`. Because both
independent decoders received the same clipped boundary, hypothesis arbitration
cannot restore the word without inventing speech.

An earlier boundary experiment changed the VAD threshold, endpoint silence,
and symmetric context together and regressed the same-audio transcript. The
new evidence supports a narrower change affecting only audio before the
detected start.

## Decision

Increase retained leading context for formal-Arabic turns from 450 ms to
750 ms. Keep trailing context at 450 ms, endpoint silence at 550 ms, and every
Tunisian-profile value unchanged. Continue using real captured PCM; do not
complete phrases from a lexicon or language model.

## Consequences

- Short weak opening particles such as `في` have an additional 300 ms of real
  audio available to both final ASR and speaker embedding.
- Endpoint detection is not delayed because the extra audio was captured
  before speech detection.
- Qwen processes at most 300 ms more audio per formal turn, which may add a
  small amount of final-refinement work but does not delay streaming partials.
- The change is isolated in the formal profile and remains independently
  tunable or reversible after field comparison.
