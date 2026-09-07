# LinTO ASR Arabic Tunisia Android evaluation pack

This pack uses LinTO's lighter Kaldi TDNN graph through Vosk 0.3.45. It is
trained specifically for Tunisian Arabic, includes French/English code-switch
capabilities, and is supplied upstream for Android and Raspberry Pi use.

Install the pinned model from PowerShell at the repository root:

```powershell
& .\tools\install-linto-vosk.ps1
```

The upstream model and Vosk runtime are Apache-2.0. Aurisia verifies the source
archive before extraction and fingerprints the complete extracted model tree
before loading it.

Published upstream results vary by test set. The TunSwitch code-switched set is
reported at 20.51% WER and 17.72% CER. Those figures are not Aurisia results;
the local `aeb-tn-field-v0_1` report remains the acceptance evidence for this
desktop proof of concept.

On the reference i7-1165G7, Aurisia's initial streaming replay measured 35.2%
WER, 10.1% CER, 66.7% code-switch retention, 106 ms mean finalization, and
176 ms maximum finalization across 11 private phrases. This small,
speaker-specific fixture is suitable for regression and adapter selection, not
for claiming general Tunisian recognition quality.
