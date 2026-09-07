# Model installation area

Model binaries are intentionally excluded from source control.

Each installed model pack must include:

- stable model ID and version;
- runtime and input audio contract;
- SHA-256 checksums;
- license and provenance;
- locale and code-switch capabilities;
- disk, memory, and thread requirements;
- reference-machine latency and accuracy results.

The installed Silero VAD pack is multilingual and independent of the Tunisian
language pack. Its ONNX binary remains ignored by Git; its manifest and
installation instructions are versioned under `silero-vad-v6.2.1/`.

The LinTO Tunisian Android pack is the active desktop ASR candidate. It runs
through Vosk, supports x86_64 and ARM CPU targets, and is Apache-2.0. Its model
directory is verified as one deterministic tree before loading. Local corpus
results remain a regression signal rather than a production accuracy claim.

Quantized generic Arabic Moonshine remains a fast but rejected language-quality
baseline with restricted non-English weights. Multilingual Whisper small-q5_1
remains a slower comparison adapter.
