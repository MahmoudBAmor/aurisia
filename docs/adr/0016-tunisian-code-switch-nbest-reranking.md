# ADR 0016: Tunisian code-switch n-best reranking

- Status: Rejected after Android field testing
- Date: 2026-09-02

## Context

Mobile testing found reduced Tunisian accuracy around embedded French and
brand words, for example `pharmacie` and `Panadol`. Inspection of the pinned
LiNTO graph confirmed that its vocabulary already contains `pharmacie`,
`فارماسي`, `باكو`, and `بانادول`. Adding display substitutions cannot recover
a word when the decoder ranked another acoustically plausible sentence first.

A fixed Vosk grammar would improve a small list of phrases by excluding normal
conversation. That is inappropriate for open live transcription.

## Decision

Request at most three Vosk alternatives only for the Tunisian profile and
expose them through the native adapter. Select among them through the generic
`TranscriptCandidateSelector` port.

The first selector is an asset-driven Tunisian code-switch policy. It gives
small additive weights to known Arabic/French forms and only changes Vosk's
choice when the alternative remains within 0.10 confidence of the decoder's
best hypothesis. It returns one of Vosk's verbatim candidates; it never inserts
or rewrites words. Alternatives without confidence retain decoder order.

Keep display transliteration separate from candidate selection. The former
changes script after recognition; the latter changes which decoder hypothesis
is accepted.

## Consequences

- Near-tied hypotheses that retain pharmacy, medicine, and common French terms
  can win without constraining general Tunisian dictation.
- A weak hinted alternative cannot overrule a substantially stronger decoder
  result.
- Three-best decoding may add a small amount of CPU work and JSON traffic, so
  mobile latency must be checked in field testing.
- Terms absent from every decoder alternative still require language-model or
  acoustic-model adaptation using consented, corrected recordings.

## Field outcome

The test phrase containing `pharmacie`, `paquet`, and `Panadol` was fragmented
into three turns. None of the Vosk candidates contained the intended complete
phrase, and the selector did not improve the result. The production Tunisian
composition therefore no longer requests n-best output or loads recognition
hints. ADR 0017 addresses the observed context loss at the endpoint and keeps
future model adaptation dependent on representative, corrected audio rather
than a display vocabulary.
