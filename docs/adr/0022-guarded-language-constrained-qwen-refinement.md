# ADR 0022: Guarded, language-constrained Qwen refinement

- Status: Accepted; supersedes ADR 0021's hotword and authority decisions
- Date: 2026-09-02

## Context

Android field testing exposed two failures after Qwen3-ASR became the shared
final recognizer. The Tunisian profile sometimes returned complete French or
Chinese sentences, while the sermon profile inserted fluent Arabic that was
not spoken. A captured failure reproduced the configured sermon hotwords as a
single fabricated result. Qwen hotwords are prompt context, not a constrained
vocabulary, and both Qwen and the Vosk baseline currently provide no comparable
confidence score.

## Decision

Keep Qwen behind the replaceable `TranscriptionEngine`, but remove all
profile-provided transcript-content hotwords. Set sherpa-onnx's per-stream Qwen
language option to `Arabic` for both Arabic-script profiles. This prevents
automatic language identification from drifting on short or ambiguous turns
without coupling the session pipeline to the Qwen runtime.

Treat Qwen as a guarded candidate rather than an authoritative unscored
rewrite. The model-neutral hypothesis policy accepts it only when it agrees
with the Vosk baseline, preserves the beginning and ending, or has independent
alternative/confidence evidence. A prefix or suffix match alone is insufficient
when the refinement is a much longer completion.

## Consequences

- French loans remain acoustic evidence, not prompt text. Qwen may still emit
  them in Arabic or Latin script, but they can no longer steer every turn.
- Fluent hallucinations and unrelated-language results no longer overwrite a
  usable Vosk baseline merely because Qwen returned non-empty text.
- Some genuinely better but substantially different Qwen results will be
  rejected until a calibrated score or a third independent hypothesis is
  available. This favors accessibility precision over speculative correction.
- No model-pack or UI contract changes are required; only profile composition,
  adapter options, and model-neutral arbitration change.
