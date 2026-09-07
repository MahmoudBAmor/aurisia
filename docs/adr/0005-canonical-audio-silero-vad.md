# ADR 0005: Canonical audio and Silero VAD

- Status: Accepted
- Date: 2026-07-29

## Context

Windows microphones expose different native sample rates and channel layouts.
Model adapters must not depend on a particular device format. The temporary
energy detector also treats loud transients as speech.

## Decision

Keep capture in the device's native format, then adapt it through a streaming
`AudioSource` that produces fixed-duration 16 kHz mono PCM. Desktop uses SoXR;
other platforms may provide another adapter behind the same contract.

Use the official Silero VAD 6.2.1 ONNX artifact with CPU-only ONNX Runtime.
Load it from an external strict manifest and verify its file size and SHA-256
before session creation. The adapter owns recurrent model state and converts
the canonical 20 ms stream into non-overlapping 512-sample inference windows.
The energy adapter remains an explicit configuration fallback.

## Consequences

Device selection no longer constrains model input. VAD is multilingual,
offline, GPU-independent, and portable to ONNX Runtime Mobile. The desktop
adds small NumPy, SoXR, and ONNX Runtime dependencies. Model binaries require a
one-time installation but are never fetched during application runtime.
