# Contributing to Aurisia

Thank you for helping improve accessible, offline transcription for Tunisian
Arabic and formal Arabic.

## Ground rules

- Keep model and platform integrations behind the existing domain ports.
- Do not make presentation code depend on a specific ASR, VAD, or speaker
  model.
- Add or update an architecture decision record for a durable architectural
  choice.
- Do not commit model weights, native runtimes, installable applications,
  microphone recordings, field transcripts, credentials, or signing material.
- Use only recordings for which every speaker has consented to the stated
  evaluation purpose.
- Describe accuracy changes with repeatable evidence. Do not present a small
  private corpus as a production benchmark.

Read `docs/architecture.md`, `PRIVACY.md`, and the relevant decision records
before changing a service boundary or data flow.

## Set up the desktop project

Python 3.12 is recommended on Windows 11:

```powershell
$venv = "$env:LOCALAPPDATA\venvs\aurisia"
py -3.12 -m venv $venv
& "$venv\Scripts\python.exe" -m pip install --upgrade pip
& "$venv\Scripts\python.exe" -m pip install -e ".[audio,desktop,inference,transport,dev]"
```

Model weights are installed separately through the checksum-verifying scripts
under `tools/`.

## Set up the mobile project

Install Flutter and the Android SDK, then run from the repository root:

```powershell
& .\tools\install-mobile-models.ps1
Set-Location .\mobile
flutter pub get
```

For interface work that does not need the local models:

```powershell
flutter run --dart-define=AURISIA_DEMO=true
```

## Required checks

Run the relevant checks before opening a pull request:

```powershell
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\python.exe" -m ruff check .
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\python.exe" -m mypy src tests
& "$env:LOCALAPPDATA\venvs\aurisia\Scripts\python.exe" -m pytest

Set-Location .\mobile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

Before a public commit, stage the intended files and run:

```powershell
Set-Location ..
python .\tools\check_public_repo.py
```

## Pull requests

A focused pull request should explain the user, the chosen boundary, tests, and
privacy or model-license implications. Keep unrelated formatting or generated
files out of the change. New model manifests must include immutable source
references, expected sizes, SHA-256 hashes, runtime contracts, and licenses.

Contributions are licensed under Apache License 2.0 unless explicitly marked
otherwise.
