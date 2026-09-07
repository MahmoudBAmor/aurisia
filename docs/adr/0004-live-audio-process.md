# ADR 0004: Live audio process

- Status: Accepted
- Date: 2026-07-29

## Context

Desktop capture must continue independently of inference latency, expose
device failures clearly, and establish the process boundary later inference
services will follow. Audio must remain local and private by default.

## Decision

Use a `sounddevice.RawInputStream` adapter for 16-bit PCM capture on Windows.
The callback performs no inference: it writes to a bounded queue, dropping the
oldest frame under overload. A supervised child process streams frames over a
loopback-only gRPC endpoint and exposes standard and contract-level health
checks. The application client remains an `AudioSource`, so downstream services
do not depend on gRPC or PortAudio.

Audio is retained only in bounded memory. Diagnostic probes report continuity
and level but do not save samples.

## Consequences

The desktop can isolate and restart capture without changing the perception
pipeline. The same downstream composition can use a native mobile source.
Queue drops and gRPC sequence gaps are observable. More process startup and
shutdown behavior must be tested than in the deterministic composition.
