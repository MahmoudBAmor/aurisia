# Moonshine Base Arabic quantized evaluation pack

This 135 MB Arabic ASR candidate uses quantized ORT artifacts through
`sherpa-onnx` 1.13.2. It is CPU-only and has a native Android deployment path.

Install the pinned model from PowerShell at the repository root:

```powershell
& .\tools\install-moonshine.ps1
```

The model is not Tunisian-specific. It must pass Aurisia's Tunisian and
French-code-switch evaluation before acceptance.

The non-English weights use the Moonshine AI Community License. That license
restricts commercial use, including internal company use, based on registration
and annual revenue. This pack is therefore an evaluation candidate only; do
not ship it without an approved enterprise license or replacement weights.
