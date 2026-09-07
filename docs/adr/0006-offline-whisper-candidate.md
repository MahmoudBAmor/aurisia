# ADR 0006: Offline Whisper ASR candidate

- Status: Accepted for model evaluation; runtime transport superseded by ADR 0007
- Date: 2026-07-29

## Context

The desktop proof of concept needs real Tunisian speech transcription on the
Windows 11 reference laptop without a GPU or network access. The later mobile
host must not require changes to the speech service, pipeline, or HUD.

## Decision

Use the multilingual Whisper small-q5_1 model with whisper.cpp 1.8.5 as the
first ASR candidate. Pin and checksum both artifacts. Feed it only canonical
16 kHz mono, VAD-delimited PCM; force source language `ar`; preserve raw model
text before Arabic-script display normalization.

The initial Windows adapter invoked the native CLI without a shell and owned
its temporary WAV/text interchange. The `SpeechEngine` interface remained
unaware of whisper.cpp. The scripted adapter stayed available by
configuration. ADR 0007 replaces only this runtime transport.

## Consequences

The live HUD now displays actual offline speech. Quantization keeps the model
pack near 181 MiB and the same model format has native mobile runtimes. The
initial desktop CLI bridge reloaded the model for each complete utterance and
briefly used a private temporary WAV. ADR 0007 records its replacement by a
persistent local service without changing the application service or
contracts.

Whisper does not explicitly model Tunisian Arabic. Accuracy, code-switch
retention, latency, and memory remain an evaluation gate before this candidate
is called production-ready.
