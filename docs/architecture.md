# Architecture

## Goals

Aurisia must run offline on the Windows 11 reference laptop without a discrete
GPU, keep every AI model replaceable, and preserve a credible path to an
Android or iOS host.

The architecture separates four concerns:

1. Domain contracts describe audio observations and perceptions.
2. Services apply one business capability and own their model ports.
3. Transport adapters decide whether those services communicate in-process or
   through local gRPC.
4. Platform applications capture devices and render perceptions.

The Python desktop and Dart mobile implementations apply this dependency rule
independently. They share architectural contracts and model-pack semantics;
they do not share runtime-specific model objects.

## Dependency rule

Code inside `aurisia.services.<service>` may import:

- Python's standard library;
- `aurisia.contracts`;
- its own ports and adapters.

It may not import another service. The automated boundary test enforces this.
Only `aurisia.application` composes concrete services.

## Service boundaries

| Service | Input | Output | Replaceable port |
|---|---|---|---|
| Audio capture | Device or file | `AudioFrame` | `AudioSource` |
| Audio normalization | Native PCM | 16 kHz mono PCM | `AudioSource` adapter |
| VAD | `AudioFrame` | `VoiceActivity` | `VadEngine` |
| Speech | VAD-delimited `AudioFrame` stream | `TranscriptEvent` | `SpeechEngine`, optional `StreamingSpeechEngine` |
| Sound detection | `AudioFrame` | `SoundEvent` | `SoundEngine` |
| Localization | Audio plus event interval | `DirectionEstimate` | `LocalizationEngine` |
| Perception | Transcript/sound plus direction | `PerceptionEvent` | Deterministic policy initially |
| HUD | `PerceptionEvent` | Visual state | Platform renderer |

Localization observes audio in parallel. A future microphone-array adapter
therefore receives synchronized multichannel samples instead of attempting to
infer direction from classification labels.

## Timing and backpressure

All timestamps are relative monotonic milliseconds belonging to an audio
stream. Audio sequences are strictly increasing. The production transport will
use bounded queues; capture must never wait for inference. Each consumer will
declare an explicit overload policy and expose dropped-frame metrics.

The live audio process uses a bounded callback queue and drops the oldest frame
under overload so capture never waits for a consumer. Capture sequence numbers
are assigned before queueing, making dropped frames visible as gaps to the gRPC
client and diagnostics. The rolling buffer is memory-only and bounded by
configuration.

Desktop capture remains in its native format. A streaming SoXR adapter
downmixes and resamples it to fixed-duration 16 kHz mono frames before any
model sees it. The adapter resets its DSP state at an observable source
sequence gap. Mobile currently requests canonical 16 kHz mono PCM directly;
a device-compatibility resampler can be added behind `PcmAudioInput` without
changing consumers.

The 60 FPS requirement applies to animation. ASR, sound classification, and
localization publish at their own cadence, and never run on the UI thread.
The VAD segmenter retains configurable memory-only audio before speech onset
so model detection latency does not clip initial phonemes. It also uses a
bounded silence window before finalization to balance natural pauses against
post-speech latency. Streaming-capable speech engines receive ordered frames
as they arrive; other engines continue to receive one complete
`SpeechSegment`. This capability extension does not leak a model runtime into
the pipeline. Engines may additionally expose non-final hypotheses. The
pipeline publishes changed partial text under one stable event identity and
uses a profile-specific hard cap, so continuous speech remains visible and
memory stays bounded even when VAD never reaches silence.

Streaming decoder output passes through a model-neutral hypothesis policy. A
partial becomes stable only after repeated observations. The normal final is
accepted when it agrees with, extends, or is materially more confident than
that partial; otherwise the stable partial is finalized instead. Optional
second-pass recognizers declare whether their unscored result is a guarded
candidate or the profile's authoritative final. The policy logs only event
identity, decision reason, and similarity—not speech text. It can therefore be
tuned or tested independently of Vosk, Audar, Whisper, capture, and
presentation.

On mobile, a `ContextPaddingSpeechSegmenter` decorates the native VAD with a
bounded chronological PCM history. It expands completed Tunisian turns by up
to 250 ms on each side. Formal turns retain up to 750 ms before the detected
start and 450 ms after the detected end, using actual captured audio already
available when the endpoint fires. It does not delay detection and falls back
to the original VAD segment if complete context is unavailable. This addresses
native VAD boundary clipping without embedding padding logic in ASR or speaker
adapters.

## Tunisian Arabic

The locale is `aeb-TN` and the selected display mode is Arabic/RTL. ASR output
and display output are separate fields. A conservative offline lexicon
transliterates only known code-switched terms; unknown words remain untouched.
This prevents presentation rules from corrupting the model transcript.

A separate evaluation composition records speech only after explicit operator
confirmation. It stores canonical WAV fixtures outside source control and
replays them through the same `SpeechRecognitionService` used by the product.
Corpus manifests version Arabizi prompts, Arabic references, and code-switch
aliases independently from private audio. Model comparison therefore changes
only the configured `SpeechEngine`.

## Model packs

Models are external, checksum-verified packs and are not committed to Git. A
pack must declare its identifier, version, runtime, license, locale, supported
hardware, expected input format, and benchmark results. Model selection is
configuration, not a conditional inside the HUD or fusion service.

Silero VAD 6.2.1 is the first production model pack. Its adapter calls ONNX
Runtime directly with one CPU thread and owns recurrent state plus 512-sample
windowing. Frames that have not yet completed a model window produce a pending
result; the VAD state machine does not count that as silence.

The active ASR pack is LinTO's Tunisian Android model through pinned Vosk
0.3.45. The model remains loaded for the application session while isolated
per-utterance decoders consume 20 ms canonical PCM frames. Decoder-internal
endpoints are collected and combined before the final transcript, preserving
phrases across natural pauses.

The final 11-phrase local streaming report measured 35.2% WER, 10.1% CER,
66.7% code-switch retention, 106 ms mean finalization, and 176 ms maximum
finalization. These numbers select a desktop candidate; the small,
speaker-specific corpus cannot establish production accuracy. The Apache-2.0
model, Vosk's native runtimes, and the upstream Android-oriented pack preserve
a credible mobile path.

Android now selects the full Tunisian STT Kaldi graph through Vosk 0.3.75
behind a native method-channel adapter. It supersedes the simplified Android
graph after field tests showed insufficient code-switch accuracy. The model is
composed with Silero VAD and a
3D-Speaker ERes2Net embedding model. Vosk owns a persistent native model and a
dedicated worker; speaker extraction remains in a persistent Dart isolate. An
online clusterer assigns stable speaker numbers only within the current
session; real identity and overlapping-speech separation are outside that
contract. The Omnilingual 300M CTC adapter remains a replaceable source
adapter, but its weights are excluded from the current Android APK.

The Tunisian profile uses Vosk's best decoder result directly. It does not load
or execute a generative final recognizer: real-device diagnostics showed that
Qwen changed correct dialect into worse Arabic and damaged French medicine
terms. Conservative display aliases can normalize an observed full phrase,
but they never invent an unknown word in arbitrary context.

The clusterer retains a bounded pool of unconfirmed voice candidates rather
than one consecutive-turn candidate. A new voice can therefore be confirmed
across A-B-A-B conversation patterns. Candidates expire after a bounded number
of turns, require three coherent embeddings, and never contaminate a known
centroid before confirmation. A switch margin keeps the previous speaker when
two known centroids are too close to call; a clear match still switches
immediately. Diagnostic builds log only similarities and decision reasons,
never embeddings or audio.

The formal mobile profile composes two independent ASR adapters. MGB-2/Vosk
publishes streaming partial and provisional final text. Qwen3-ASR 0.6B INT8
refines completed turns through the pinned sherpa-onnx CPU runtime while
speaker extraction runs independently. Both results upsert the same event, so
final quality does not delay visible text and either model can be replaced
without changing presentation or microphone capture. The model receives the
per-stream `Arabic` language hint and no transcript-content prompt. Empty,
repetitive, implausibly expanded, or failed output preserves Vosk. The formal
profile owns a conservative display lexicon and can accept a divergent Qwen
result only when a multiword Vosk baseline retains measurable acoustic overlap;
this recovers cropped formulaic phrases without trusting one-word completions.

Final refinement has bounded back-pressure. One inference may be active and at
most the newest waiting turn is retained; intermediate waiting turns keep
their Vosk text. Results older than the profile's freshness limit are not
published. Speaker clustering has its own ordered future and therefore no
longer waits for generative decoding. Long sessions cannot build an unbounded
Qwen queue or progressively increase visible latency.

For final adapters that need it, a replaceable
`SpeechTurnPreprocessor` may shorten sustained phonation longer than 900 ms to
about 560 ms. Detection uses bounded linear-time waveform features and a
crossfaded cut; it does not infer or rewrite words. Vosk streaming and speaker
embeddings always consume the original PCM. This experimental expressive-speech
treatment remains isolated from presentation and identity. Qwen3 continues to
receive the original waveform after correctly recovering a three-second
prolonged vowel in field diagnostics. Conversation retains a four-second
final-result freshness limit; formal Arabic uses eight seconds so a useful
correction is not discarded just beyond the generic limit.

Mobile endpoint silence is profile-specific: 500 ms for Tunisian conversation
and 550 ms for formal Arabic. Formal speech is forcibly finalized after 14
seconds instead of 20 so CPU refinement work and visible delay remain bounded.
Streaming partials remain immediate. These
values favor enough lexical and vocal context to keep one sentence—and its
speaker embedding—together, without changing decoder frame cadence or the ASR
interface.

Flutter bundles the full Tunisian model's checksum-pinned 542 MB archive for
Android. The native installer streams it into private storage, validates the
archive, extracts it without accepting traversal paths, fingerprints the
complete 1.46 GB output
tree, and returns a model-directory role to the composition layer. File-based
VAD, speaker, and final-ASR artifacts use the same versioned contract. Qwen3's
frontend, INT8 encoder/decoder, tokenizer, license, and notice are
checksum-pinned in a shared contract. The UI never knows filenames or model
runtimes. A store build can replace bundled assets with Play Asset Delivery
without changing inference ports.

The turn-based portable mobile session consumes VAD turns through a three-item bounded queue. If
inference falls behind, it drops the oldest pending turn and records the drop
count, preserving recent audio and preventing unbounded memory growth. Live
profiles use bounded VAD rollover values so uninterrupted speech cannot grow
decoder state indefinitely.

Generic Arabic Moonshine remains the speed baseline but was rejected for
Tunisian quality after 77.8% WER, 35.3% CER, and zero code-switch retention on
the same corpus. Whisper small-q5_1 remains a comparison adapter and sends an
in-memory WAV to a pinned, persistent whisper.cpp CPU service on loopback. No
runtime crosses the speech port. Empty decoder output is a valid no-transcript
result, so a VAD false positive cannot stop the pipeline.

The Flutter presentation uses a light, high-contrast theme by default. Arabic
transcript text is 24 px before operating-system scaling, primary controls have
at least 52 px touch targets, and speaker cards combine a number, dark AA text
color, a thick edge, and a subtle tint. Accessibility styling depends only on
the session-neutral `speakerIndex`; no model or clustering behavior leaks into
the widget layer.

## Deployment evolution

- **Desktop:** live audio is a supervised loopback process; LinTO/Vosk,
  Moonshine, Whisper, and scripted ASR implementations are replaceable behind
  service-owned speech ports.
- **Current mobile slice:** native microphone plus replaceable Vosk and
  sherpa-onnx/Qwen3 adapters behind Dart ports, with heavy
  inference off the UI thread and self-contained versioned model packs.
- **Mobile hardening:** representative Tunisian evaluation, mobile performance
  and thermal budgets, overlapping-speech research, production signing, and
  platform asset delivery.
