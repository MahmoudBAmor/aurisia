# Aurisia

Aurisia is an offline auditory perception platform. The current product focus
turns Tunisian conversations into an accessible, multi-speaker mobile
transcript. The spatial desktop HUD remains the architectural proof of concept.

> **Project status:** experimental public beta. Aurisia is being evaluated with
> deaf and hard-of-hearing users, but it can still omit or misrecognize speech.
> It is not a guaranteed captioning, medical, safety, or emergency service.

This repository contains a deterministic vertical slice, a live desktop proof
of concept, and an Android-first Flutter transcription client. They prove the
service boundaries, Tunisian Arabic display pipeline, local microphone
transport, model-backed voice activity detection, offline speech recognition,
and session-local speaker attribution.

## Current capabilities

- Immutable, implementation-neutral audio and perception contracts.
- Versioned Protobuf/gRPC transport schema under `aurisia.v1`.
- Strict offline configuration for the Windows 11 x64 reference machine.
- Replaceable ports for audio, VAD, ASR, sound classification, and localization.
- Deterministic PCM source and WAV replay adapter.
- Windows microphone discovery and live 16-bit PCM capture.
- Supervised loopback gRPC audio service with bounded queues and drop metrics.
- Streaming native-format normalization to canonical 16 kHz mono PCM.
- Checksum-verified Silero VAD 6.2.1 through CPU-only ONNX Runtime.
- Persistent LinTO Tunisian/Vosk CPU recognition behind `SpeechEngine`.
- Checksum-verified Tunisian Android model with Apache-2.0 provenance.
- Optional partial ASR updates during continuous speech with bounded sessions.
- Moonshine and whisper.cpp retained as replaceable comparison adapters.
- Configurable speech pre-roll and total/finalization ASR latency diagnostics.
- Arabic-script Tunisian normalization with raw transcripts preserved.
- Opt-in local Tunisian corpus recording and model-neutral WER/CER evaluation.
- Priority/fusion service and renderer-neutral `PerceptionEvent`.
- PySide6/QML transparent, always-on-top, click-through HUD shell.
- Architecture tests that prevent services from importing one another.
- Android-first Flutter host with an Arabic/RTL multi-speaker transcript.
- Android LiNTO/Vosk Tunisian ASR with a checksum-verified archived model pack;
  Omnilingual remains a portable comparison adapter.
- Formal Arabic uses immediate MGB-2/Vosk text plus guarded Qwen3-ASR 0.6B
  INT8 final refinement. Tunisian conversation remains on the field-tested full
  Vosk model because generative refinement regressed dialect and code-switches.
- Mobile ASR and 3D-Speaker attribution behind replaceable Dart ports, with
  native and isolate CPU work kept off the UI thread.
- Incremental mobile partial transcripts, asynchronous formal-ASR correction,
  and bounded multi-candidate speaker clustering that handles A-B-A-B turns.

Live VAD and ASR are model-backed. LinTO/Vosk is the current Tunisian desktop
candidate based on the local starter corpus, not yet a production accuracy
commitment. Sound classification and localization remain deterministic
development adapters.

## Start with the mobile interface

The model-free demo exercises the Android/Flutter presentation and application
boundaries without downloading model weights:

```powershell
Set-Location .\mobile
flutter pub get
flutter run --dart-define=AURISIA_DEMO=true
```

For live offline recognition, install the checksum-verified model packs first:

```powershell
Set-Location ..
Set-ExecutionPolicy -Scope Process Bypass
& .\tools\install-mobile-models.ps1
Set-Location .\mobile
flutter run
```

The source checkout does not contain model weights, recordings, field
transcripts, native runtimes, APKs, or signing keys. See
[`mobile/README.md`](mobile/README.md) for Android setup and model storage
requirements.

## Run the deterministic pipeline

Python 3.12 is recommended. The source is compatible with Python 3.10+ so the
contract and architecture tests can also run in lightweight environments.

### Windows 11

The repository is inside a deeply nested OneDrive folder. Keep the virtual
environment in a short per-user path so Windows can extract Qt's QML files
without exceeding the legacy path-length limit.

```powershell
$venv = "$env:LOCALAPPDATA\venvs\aurisia"
py -3.12 -m venv $venv
& "$venv\Scripts\python.exe" -m pip install --upgrade pip
& "$venv\Scripts\python.exe" -m pip install -e ".[audio,desktop,inference,transport,dev]"
& "$venv\Scripts\python.exe" -m aurisia --compact
```

Install the pinned VAD artifact once using the command in
[`models/silero-vad-v6.2.1/README.md`](models/silero-vad-v6.2.1/README.md).
Then install the active CPU-only Tunisian LinTO/Vosk model:

```powershell
& .\tools\install-linto-vosk.ps1
```

Aurisia verifies artifact sizes and SHA-256 checksums before loading them. The
installer requires network access; the application does not. The model and
Vosk runtime are Apache-2.0 and the lighter pack is intended upstream for
Android and Raspberry Pi. See the model pack's
[`README.md`](models/linto-asr-ar-tn-android-v0.1/README.md).

The generic Arabic Moonshine and slower multilingual Whisper candidates remain
available for comparisons:

```powershell
& .\tools\install-moonshine.ps1
& .\tools\install-whisper.ps1
```

Moonshine's non-English weights use a restricted community license.

Launch the desktop HUD:

```powershell
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\aurisia-desktop.exe"
```

Inspect the microphones Windows exposes, then verify one second of live audio:

```powershell
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\aurisia.exe" --list-devices
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\aurisia.exe" --probe-microphone 1
```

Launch the live desktop path:

```powershell
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\aurisia-desktop.exe" `
  --live --device "Réseau de microphones 1" `
  --sample-rate-hz 48000 --channels 2 --asr-metrics
```

Pass a device ID (or a unique device-name fragment) to select a microphone.
For devices that require their native capture format, also pass
`--sample-rate-hz` and `--channels`; for example:

```powershell
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\aurisia.exe" `
  --probe-microphone 3 --device "Réseau de microphones 1" `
  --sample-rate-hz 48000 --channels 2
```

Benchmark Silero while speaking, pausing, and making non-speech sounds:

```powershell
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\aurisia.exe" `
  --benchmark-vad 10 --device "Réseau de microphones 1" `
  --sample-rate-hz 48000 --channels 2
```

Device IDs can change, so rerun `--list-devices` after hardware changes. In the
live path, the already-loaded Vosk model decodes canonical frames while the
speaker is talking. Silero then waits about 288 ms of silence before Vosk
finalizes the current decoder. `--asr-metrics` reports total CPU work, RTF, and
the `finalize` work left after the final frame. During uninterrupted speech,
changed partial text updates the same HUD event every 750 ms. All adapters have
a 30-second safety rollover, preventing unbounded audio or decoder state.

On the 11-phrase local corpus, streaming LinTO/Vosk measured 35.2% WER, 10.1%
CER, 66.7% code-switch retention, and 106 ms mean finalization (176 ms max).
The estimated ASR response after speech is therefore about 394 ms on average:
288 ms endpointing plus 106 ms finalization, before small transport/rendering
overhead. The corpus is a regression fixture, not a representative production
benchmark.

Set `models.speech_adapter` to `scripted_aeb_tn` only when a deterministic
development fallback is useful. Switching to `whisper_cpp` also requires
pointing `speech.model_manifest_path` back to the Whisper pack.

## Evaluate Tunisian speech models

Aurisia includes a versioned starter corpus containing the phrases used during
the first Tunisian desktop tests. Review its provisional Arabic references in
[`aeb-TN-field-v0.1.yaml`](evaluation/corpora/aeb-TN-field-v0.1.yaml), then
record them with the same microphone configuration:

```powershell
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\aurisia.exe" `
  --record-asr-corpus .\evaluation\corpora\aeb-TN-field-v0.1.yaml `
  --device "Réseau de microphones 1" `
  --sample-rate-hz 48000 --channels 2
```

This command displays a privacy notice and requires typing `RECORD` before it
opens the microphone. It saves VAD-delimited canonical WAV files under
`recordings\aeb-tn-field-v0_1`, which is excluded from source control. Existing
files are skipped so an interrupted session can resume safely.

Evaluate the recordings through the currently configured speech adapter:

```powershell
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\aurisia.exe" `
  --evaluate-asr-corpus .\evaluation\corpora\aeb-TN-field-v0.1.yaml `
  --asr-report .\recordings\linto-vosk-streaming-aeb-tn-v0.2.json
```

The schema-v2 report contains raw and display transcripts, WER, CER, French
code-switch retention, total recognition work, finalization latency, RTF, and
aggregate results. A report path must be new, preventing accidental
replacement of an earlier model result. Change only the configured speech
adapter and model pack to compare another engine against exactly the same
private recordings. See
[`evaluation/README.md`](evaluation/README.md) for corpus and scoring details.

## Existing WSL environment

```bash
PYTHONPATH=src python3 -m aurisia --compact
PYTHONPATH=src python3 -m unittest discover -s tests -v
```

## Architecture

Each service owns its model-facing port and adapters. Services exchange only
types from `aurisia.contracts`; the application composition layer is the only
code allowed to connect implementations.

```text
Native audio ─> Normalization ─┬─> VAD ─> Speech ─┐
                              ├─> Sound ─────────┼─> Perception/Fusion ─> HUD
                              └─> Localization ──┘
```

The deterministic demo is fully in-process. Live desktop capture runs as a
supervised loopback process. Normalization, Silero, and the active native ASR
adapter sit behind replaceable service-owned ports; the composition layer is
the only place that chooses their implementations. Streaming is an optional
speech capability, so complete-segment adapters still obey the original port.
The Whisper fallback keeps its independently supervised loopback process.
The mobile host already applies the same boundary rule in Dart: recording,
segmentation, ASR, speaker attribution, session composition, and presentation
depend on model-neutral ports. See [`mobile/README.md`](mobile/README.md) for
the Android run and build workflow.

Regenerate the checked-in Python bindings after changing the schema:

```powershell
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\python.exe" -m grpc_tools.protoc `
  -Icontracts/proto --python_out=src --pyi_out=src --grpc_python_out=src `
  contracts/proto/aurisia/v1/aurisia.proto
```

See [architecture.md](docs/architecture.md) and the decision records in
[`docs/adr`](docs/adr).

## Privacy

Audio is not retained by default. The active Vosk adapter consumes ordered PCM
frames directly from memory and resets a persistent decoder after each turn.
The Whisper fallback serializes segments to an in-memory WAV and
sends them only to its supervised loopback process; Aurisia does not create a
temporary audio file. WAV recordings and model binaries are ignored by source
control. Any diagnostic recording mode must be explicit, visibly indicated,
and bounded by a retention policy.

On mobile, completed speech turns are passed in memory to the local
Qwen3-ASR/sherpa-onnx worker isolate. They are never uploaded or written as a
temporary recording.

The complete source-level privacy description is in [`PRIVACY.md`](PRIVACY.md).

## Contributing and public releases

Contributions are welcome. Read [`CONTRIBUTING.md`](CONTRIBUTING.md) before
submitting code or evaluation material. In particular, never commit a real
recording, transcript, model weight, application-signing key, or generated APK.

Before the first public push or any release, follow
[`docs/public-release.md`](docs/public-release.md) and run:

```powershell
python .\tools\check_public_repo.py
```

Aurisia source code is licensed under the
[Apache License 2.0](LICENSE). Models and third-party dependencies retain their
own licenses; see [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md).
