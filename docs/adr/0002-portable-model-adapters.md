# ADR 0002: Portable model adapters

- Status: Accepted
- Date: 2026-07-29

## Context

The reference computer has a CPU-only requirement, while the product must later
run on mobile devices. Tunisian ASR quality is not yet proven for one model.

## Decision

Each inference service owns a small model port. The initial candidate runtimes
are whisper.cpp for speech and ONNX Runtime for suitable VAD and classifier
models. Runtime-specific tensors and sessions remain inside adapter packages.

Models are selected by validated configuration and installed as external packs
with checksums and license metadata.

## Consequences

Aurisia can benchmark or replace an engine without changing fusion or the HUD.
Fine-tuned Tunisian models remain an evidence-based selection rather than an
architectural commitment.
