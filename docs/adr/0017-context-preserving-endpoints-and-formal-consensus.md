# ADR 0017: Context-preserving endpoints and formal-ASR consensus

- Status: Accepted
- Date: 2026-09-02

## Context

Android field testing showed one continuous Tunisian request split into three
short transcript cards. French and medicine words lost their sentence context,
and the short fragments were assigned to a second speaker. The code-switch
n-best experiment could not recover the sentence because the intended words
were absent from every candidate.

Formal Arabic has a different failure mode: Vosk often produces a nearly
correct result and Whisper proposes a small correction without a confidence
score. Relaxing the existing gate globally would again allow a divergent
second-pass result to replace a good visible transcript.

## Decision

Use 500 ms endpoint silence for Tunisian conversation and 650 ms for formal
sermons. Continue publishing changed streaming partials immediately. Keep the
hard maximum-speech limit, so uninterrupted speech and memory remain bounded.

Remove Tunisian lexical n-best selection from the production composition and
accept Vosk's best candidate. Keep conservative display aliases independent of
recognition.

For formal Arabic only, request at most three scored Vosk candidates and retain
them as hypothesis metadata. Accept the unscored Whisper refinement when it
either meets the existing direct-agreement threshold or has at least 0.88 text
similarity with either of Vosk's first two candidates. Candidate rank is used
instead of treating Vosk's sentence-level alternative score as a calibrated
probability. Otherwise preserve the streaming baseline. Keep this arbitration
in the model-neutral application policy.

Do not increase the bundled Whisper model solely on package-size tolerance.
The current mobile runtime uses greedy decoding, and a larger model must first
beat the current hybrid on a consented formal-Arabic corpus within device RAM,
latency, and thermal budgets.

## Consequences

- Natural within-sentence pauses are less likely to fragment Tunisian text or
  create speaker identities from short audio fragments.
- Finalization can occur about 280 ms later for Tunisian and 330 ms later for
  formal Arabic than under ADR 0015; streaming partial text remains visible.
- Small formal-Arabic corrections gain independent cross-model support without
  granting Whisper unconditional authority over the visible transcript.
- Formal n-best metadata adds bounded native JSON and policy work; it does not
  enter presentation code.
- Code-switch terms missing from all decoder candidates still require measured
  language/acoustic model adaptation using corrected recordings.
