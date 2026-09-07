# Whisper small-q5_1 model pack

This is the multilingual, quantized Whisper `small` candidate for Tunisian
Arabic evaluation. The binary is intentionally ignored by Git.

Install the pinned CPU runtime and model from PowerShell at the repository root:

```powershell
& .\tools\install-whisper.ps1
```

The installer pins immutable URLs, expected sizes, and SHA-256 hashes. Aurisia
verifies the model manifest and the whisper.cpp executable again at startup.
No network access is used while transcribing.
