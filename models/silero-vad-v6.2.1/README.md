# Silero VAD 6.2.1 model pack

The ONNX binary is intentionally ignored by Git. Install it once from the
pinned upstream release:

```powershell
Invoke-WebRequest `
  -Uri "https://raw.githubusercontent.com/snakers4/silero-vad/v6.2.1/src/silero_vad/data/silero_vad.onnx" `
  -OutFile "models/silero-vad-v6.2.1/silero_vad.onnx"
```

Aurisia verifies the declared file size and SHA-256 checksum in
`manifest.yaml` before creating an inference session. Runtime inference is
offline and CPU-only.
