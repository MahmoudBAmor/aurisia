# ADR 0012: Offline mobile multi-speaker transcription

- Status: Accepted; initial ASR selection superseded by ADR 0013
- Date: 2026-09-01

## Context

The product priority moved from the desktop HUD to an Android-first
transcription application, while keeping a credible iOS path. The initial
mobile experience needs Tunisian Arabic in Arabic script, session-local speaker
separation, no network dependency, and replaceable AI models. Package size may
approach 1 GB when that materially improves Tunisian recognition.

Flutter assets are inside the application bundle, while sherpa-onnx model APIs
require ordinary filesystem paths. Loading a 365 MB asset through
`rootBundle.load` would also create an avoidable large allocation on the Dart
UI isolate.

## Decision

Use Flutter for the application and presentation layer, with Android and iOS
native code limited to streamed model-pack materialization. The native
installer copies one megabyte at a time into private application storage,
checks the declared byte count and SHA-256, and writes a checksum marker after
an atomic commit. Later launches reuse a matching installed artifact.

Compose the live pipeline from independent Dart interfaces:

- `PcmAudioInput` captures canonical microphone frames;
- `SpeechSegmenter` owns VAD and turn boundaries;
- `TranscriptionEngine` owns ASR;
- `SpeakerAttributionEngine` owns embeddings and clustering;
- `TranscriptionSession` publishes model-neutral transcript segments.

Select the sherpa-onnx 300M Omnilingual INT8 CTC model for the first mobile ASR
pack because its declared language set includes `aeb_Arab`. Use Silero for VAD
and 3D-Speaker ERes2Net embeddings with bounded online cosine clustering for
session-local speaker attribution. Run ASR and embedding extraction in
independent persistent isolates. Cap VAD turns at six seconds so continuous
speech cannot grow memory without bound or remain invisible indefinitely.

The first sideloaded APK is self-contained. A future store build will use Play
Asset Delivery behind the same model-pack materializer instead of changing the
speech or UI layers.

Keep the 1B Omnilingual INT8 model as an evaluation candidate rather than the
default. Its ASR file alone is about 1.03 GB, before the speaker model and app
runtime, and it has not yet demonstrated a Tunisian accuracy gain on Aurisia's
field corpus. The 300M variant is explicitly intended for low-power devices;
the model-pack boundary lets us A/B test the 1B pack without a UI rewrite.

## Consequences

- Android can run fully offline after installation and iOS retains the same
  service composition.
- A model can be replaced by a manifest, assets, and an engine adapter without
  changing speaker cards or microphone capture.
- The initial bundle contains about 407 MB of weights and temporarily requires
  both bundled and installed copies.
- First launch takes longer because the pack is streamed and verified; later
  launches are fast.
- Speaker labels represent clusters within one session, not enrolled people.
- Overlapping-speaker separation, persistent identities, mobile accuracy
  measurement, thermal profiling, and store delivery remain explicit later
  milestones.
