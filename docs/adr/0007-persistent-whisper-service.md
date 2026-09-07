# ADR 0007: Persistent loopback Whisper service

- Status: Accepted
- Date: 2026-07-30

## Context

The first real ASR adapter launched `whisper-cli` for every speech segment.
That reloaded a roughly 181 MiB model and exchanged audio through temporary
files, making post-speech latency unsuitable for the desktop proof of concept.
VAD onset could also omit the first phonemes of an utterance.

## Decision

Supervise one checksum-verified `whisper-server` process for each live
application session. Bind it only to a configured loopback endpoint, wait for
its health response before capture, and stop it with the application. The
speech adapter constructs a WAV and multipart request entirely in memory and
communicates through the existing `SpeechEngine` port.

Retain 300 ms of bounded, memory-only pre-roll when VAD enters speech. Use nine
Silero windows (about 288 ms) to finalize speech after silence. Expose
per-utterance inference latency and real-time factor through an optional
measurement callback and launcher flag.

## Consequences

The model loads once per live session instead of once per utterance. No
temporary speech file is required. Service startup is several seconds longer,
but steady-state latency becomes measurable and substantially lower.

The loopback HTTP protocol is a desktop transport adapter, not a domain
contract. A mobile host can call whisper.cpp in process while preserving the
speech service, model pack, normalization contract, and HUD. Recognition
quality remains a separate model-evaluation problem; persistence and pre-roll
do not make the generic multilingual model Tunisian-specific.
