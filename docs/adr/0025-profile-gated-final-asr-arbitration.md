# ADR 0025: Profile-gated final ASR arbitration

- Status: Accepted
- Date: 2026-09-02

## Context

Opt-in Android diagnostics captured the streaming Vosk baseline, the Qwen3
final result, and Aurisia's selected text for the same speech turn. In formal
Arabic, Qwen produced substantially better text such as
`وأشهد أن لا إله إلا الله وحده لا شريك له`, while the conservative boundary
gate retained Vosk's `إلى إلا الله وحده لا شريكة`. Similar false rejections
occurred around `المستبصرين` and `لأولي الأبصار`.

The same diagnostics also confirmed why Qwen cannot be globally authoritative.
A short `أما` baseline received a speculative longer completion, and previous
prompt experiments produced unrelated or repeated text. In Tunisian speech,
Qwen correctly recovered `بانادول` in one turn but dropped meaningful words in
another.

## Decision

Keep final-result selection in the model-neutral `StreamingHypothesisPolicy`
and configure its evidence gates per transcription profile.

An unscored preferred refinement must meet all configured constraints:

- minimum normalized character similarity;
- minimum retained token-count ratio;
- minimum first-token similarity when the profile requires it; and
- maximum output-to-baseline length ratio.

Formal Arabic accepts moderate overlap because the captured Qwen output is
usually more accurate than the MGB-2 Vosk baseline. Tunisian conversation uses
stricter token and leading-word retention so a code-switched correction can win
without shortening an otherwise better phrase. Confidence-backed and
alternative-consensus paths remain unchanged.

## Consequences

- The field-observed formal corrections now reach the UI.
- Short speculative completions and gross length expansions remain rejected.
- The captured `بانادول` correction is selected while the more complete
  `وقتاش باش تمشي للفارماسي` baseline is preserved.
- Thresholds are profile configuration rather than model-adapter behavior, so
  Vosk and Qwen remain replaceable services.
- Representative consented audio and reference transcripts are still required
  to replace these field-derived gates with a measured corpus policy.
