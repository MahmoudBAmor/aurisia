# Third-party notices

Aurisia source code is licensed under Apache License 2.0. That license does not
relicense third-party libraries, runtimes, datasets, tokenizers, or model
weights. Each remains subject to its own license and acceptable-use terms.

The source repository intentionally excludes large artifacts. Model manifests
record immutable sources, expected sizes, checksums, and declared licenses;
notice and license files are retained beside a manifest when required.

## Active Android components

| Component | Purpose | Declared license | Source |
| --- | --- | --- | --- |
| Flutter | Application framework | BSD-3-Clause | <https://github.com/flutter/flutter> |
| record | Microphone capture plugin | BSD-3-Clause | <https://pub.dev/packages/record> |
| sherpa-onnx | On-device inference | Apache-2.0 | <https://github.com/k2-fsa/sherpa-onnx> |
| llama_cpp_dart | Dart llama.cpp binding | MIT | <https://pub.dev/packages/llama_cpp_dart> |
| Vosk Android | Streaming ASR runtime | Apache-2.0 | <https://github.com/alphacep/vosk-api> |
| JNA | Native access used by Vosk | Apache-2.0 or LGPL-2.1-or-later | <https://github.com/java-native-access/jna> |
| Full Tunisian STT model | Tunisian Vosk recognition | Apache-2.0 | <https://huggingface.co/Sali7a8603/Tunisian_STT> |
| Vosk MGB-2 Arabic model | Formal-Arabic streaming recognition | Apache-2.0 | <https://alphacephei.com/vosk/models> |
| Qwen3-ASR 0.6B INT8 | Formal-Arabic final recognition | Apache-2.0 | <https://github.com/k2-fsa/sherpa-onnx/releases/tag/asr-models> |
| Silero VAD | Voice activity detection | MIT | <https://github.com/snakers4/silero-vad> |
| 3D-Speaker ERes2Net | Session-local speaker embeddings | Apache-2.0 | <https://github.com/modelscope/3D-Speaker> |

Qwen's license and conversion notice are retained under
`mobile/assets/model_packs/qwen3-asr-0.6B-int8/`. The Tunisian model notice is
retained under `mobile/assets/model_packs/aeb-TN-vosk-full/`.

## Optional evaluation components

The repository also contains adapters or manifests for comparison candidates.
They are not necessarily part of the active mobile build:

- Audar ASR uses the AudarAI Open License 1.0; its full license, notice, and
  model card are retained under `mobile/assets/model_packs/ar-audar/`.
- Omnilingual and generic Whisper manifests declare their provenance and
  licenses in their respective model-pack directories.
- Moonshine non-English weights are evaluation-only because their community
  license is more restrictive than the Aurisia source license.

## Release responsibility

This inventory is a convenience summary, not a substitute for the license text
at each pinned source. Before distributing an APK, app bundle, desktop package,
or model mirror, the distributor must verify the exact artifact license and
include every notice required by the packaged dependencies. A dependency update
must update this inventory when its license, source, or role changes.
