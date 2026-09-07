# ADR 0008: Moonshine Arabic low-latency candidate

- Status: Rejected by ADR 0010
- Date: 2026-07-30

## Context

The persistent Whisper small-q5_1 service removed repeated model loading, but
real Tunisian utterances still required about eight seconds of CPU inference
after the user stopped speaking on the Windows 11 reference laptop. This is
incompatible with the desktop proof of concept and the eventual mobile target.
Changing Arabic display text to Arabizi would not address this bottleneck
because presentation happens after recognition.

## Decision

Add quantized Moonshine Base Arabic through sherpa-onnx 1.13.2 as another
`SpeechEngine` adapter and make it the active evaluation configuration. Keep
the recognizer loaded once per session, feed it only canonical 16 kHz mono PCM,
record the same model-neutral latency/RTF measurement, and preserve the raw
decoder text before Arabic-script normalization.

Pin the model archive, individual artifacts, and runtime version. Contain the
runtime-specific configuration inside the adapter so replacing Moonshine does
not affect capture, VAD, speech service, perception fusion, or the HUD.

The non-English weights use the Moonshine AI Community License. Treat the model
as evaluation-only unless commercial use is approved and licensed.

## Consequences

On the reference i7-1165G7 with four CPU threads, one official 6.546-second
Arabic sample decoded in 457 ms (RTF 0.07) after a one-time model load. This
removes Whisper's dominant compute delay in that benchmark, but it does not
prove the specification's end-to-display target and it says nothing about
Tunisian dialect or French code-switch accuracy.

The next gate is a repeatable Tunisian phrase corpus measured for raw
transcription quality and end-to-display latency. Reject or replace this model
if it fails either the language gate or the license gate; the rest of the
application remains unchanged.

The `aeb-tn-field-v0_1` result was 77.8% WER, 35.3% CER, zero code-switch
retention, and 141 ms mean recognition. Moonshine passed the CPU speed gate but
failed the Tunisian language and code-switch gates, so ADR 0010 replaces it as
the active candidate.
