# ADR 0013: Android Tunisian ASR through LiNTO/Vosk

- Status: Accepted
- Date: 2026-09-01

## Context

The first physical-device test showed that the generic Omnilingual 300M CTC
pack did not provide acceptable Tunisian transcription. Its runtime exposes no
language-conditioning input, so declaring `aeb_Arab` support does not force the
decoder toward Tunisian. Increasing the same CTC family to 1B would add about
1.03 GB of weights without measured improvement.

Aurisia already evaluated LiNTO's Android-oriented Tunisian Kaldi model on the
operator's 11 recorded phrases. It measured 35.2% WER, 10.1% CER, 66.7%
code-switch retention, and 106 ms mean finalization. This small corpus is not a
production claim, but it is materially stronger local evidence than the
unvalidated generic mobile model.

## Decision

Make LiNTO/Vosk the default Android `TranscriptionEngine`. Keep microphone
capture, VAD, speaker attribution, transcript contracts, and UI unchanged.
Implement Vosk behind a small method-channel adapter that:

- owns one persistent native model;
- creates an isolated recognizer per speech turn;
- consumes canonical 16 kHz mono PCM16;
- executes model loading and decoding on a single native worker, never the UI
  thread; and
- returns only model-neutral text and confidence fields to Dart.

Ship the pinned upstream model archive rather than 279 MB of loose assets. The
native model-pack service verifies the 166 MB archive, rejects unsafe archive
paths, extracts into a temporary directory, verifies the complete output-tree
fingerprint, and atomically commits the versioned directory. The existing
Omnilingual adapter and pack remain available for iOS and future A/B work.

## Consequences

- Android uses a Tunisian-specific model with existing local evaluation
  evidence.
- ASR selection changes only application composition and a model manifest; no
  presentation or speaker code depends on Vosk.
- First launch performs archive extraction and full-tree verification.
- The proof-of-concept bundle remains large while both Android and portable
  packs are embedded; store delivery and platform-specific packaging remain
  later work.
- iOS does not use Vosk yet. It retains the portable adapter behind the same
  `TranscriptionEngine` contract until an iOS Vosk binary or a better evaluated
  portable model is selected.
