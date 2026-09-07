# ADR 0028: Senior light UI and conservative speaker switching

- Status: Accepted
- Date: 2026-09-06

## Context

The first deaf field tester accepted the mobile workflow but found white text
on a black background uncomfortable. Field use also showed occasional false
speaker-color changes. Formal-Arabic diagnostics exposed a separate selection
failure: Qwen recovered cropped multiword phrases that the agreement gate
rejected, while genuinely speculative and repetitive Qwen output still needed
protection. The formal profile already used about 2.9 GB PSS on the reference
phone, including substantial swap, so a larger generative model would worsen
latency and memory pressure.

A 2026-09-06 replay of the first roughly 2 minutes 40 seconds of the reference
sermon measured 30.1% word error rate for Vosk, 21.2% for Qwen, and 20.7% for
the selected output against the supplied YouTube transcript. Replaying that
same output through the evidence-derived formal lexicon measured 8.8%. This is
an in-sample regression measurement, not a claim of general Fusha accuracy; a
different sermon remains necessary for unbiased evaluation. All 25 turns in
that replay stayed on one speaker, with no false color split.

## Decision

Keep the existing screen structure and gestures, but make the default theme
light and high contrast. Increase transcript type and touch targets, and encode
speaker identity redundantly through a number, accessible dark color, thick
card edge, and subtle card tint.

Require three coherent embeddings before creating a new speaker. Lower the
known-speaker match threshold slightly and add temporal switch hysteresis:
when two known speakers score within the configured margin, retain the previous
speaker. Keep the embedding model and domain port unchanged. Diagnostic builds
emit similarity scores and decision reasons, never audio or embeddings.

Give formal Arabic its own replaceable display lexicon. Broaden Qwen selection
only for multiword Vosk baselines with measurable overlap and bounded expansion;
reject repeated-token output and one-word speculative completion. Reduce the
formal hard turn cap from 20 to 14 seconds and endpoint silence to 550 ms.

## Consequences

- Existing users keep the same record, clear, language-selection, and scrolling
  interactions.
- False color changes require more consistent evidence, at the cost of assigning
  the first two turns of a genuinely new person to the previous speaker.
- Clear switches between already confirmed speakers remain immediate.
- Fusha corrections are profile-owned data and arbitration policy, not UI or
  model-runtime special cases.
- Larger ASR models remain replaceable candidates, but are not adopted without
  a representative accuracy and on-device latency win.
