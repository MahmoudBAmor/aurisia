# ADR 0010: LinTO/Vosk streaming Tunisian ASR

- Status: Accepted as the desktop evaluation candidate
- Date: 2026-07-30

## Context

Generic Arabic Moonshine decoded quickly but failed the local Tunisian gate:
77.8% WER, 35.3% CER, and zero retention of the corpus's French code-switched
terms. Changing the display script cannot repair acoustic substitutions.

LinTO publishes a Tunisian Arabic Kaldi model with French/English code-switch
support and a lighter Android-oriented pack. Both its model and the Vosk
runtime are Apache-2.0. Whole-segment decoding on the reference laptop improved
the local corpus to 33.3% WER, 12.6% CER, and 66.7% code-switch retention, but
performed about 1.56 seconds of recognition after VAD had already ended.

## Decision

Make the checksum-verified LinTO Android pack and Vosk 0.3.45 the active ASR
candidate. Keep the model loaded once, create isolated recognizers per
utterance, and decode canonical 16 kHz mono frames while they arrive.

Extend the speech service with an optional `StreamingSpeechEngine` capability.
The pipeline depends only on that service-owned protocol. Engines without the
capability keep the complete-segment `SpeechEngine` behavior, so Moonshine,
Whisper, the HUD, fusion, audio capture, and model selection do not require
model-specific branches.

Buffer frames only until the configured minimum speech duration is reached, so
short VAD false positives never allocate a decoder. Preserve Vosk's internal
endpoint results across pauses and combine them with its final result.

Replay evaluation WAVs as 20 ms frames and report both total CPU work and
finalization latency. Total work measures compute capacity; finalization
measures work left after the last audio frame.

## Consequences

The final streaming replay of the 11-phrase local corpus measured 35.2% WER,
10.1% CER, 66.7% code-switch retention, 106 ms mean finalization, and 176 ms
maximum finalization. Total recognition work averaged 1.41 seconds but was
amortized across the utterance with RTF below 1 on every case.

With the current nine-window Silero endpoint (about 288 ms), estimated
post-speech ASR response is about 394 ms on average and 464 ms at the observed
maximum, plus small transport and HUD rendering overhead. This is a major
latency improvement over complete-segment inference.

The corpus is private, speaker-specific, and only 11 phrases. Its WER also
penalizes valid Tunisian spelling and tokenization variants more heavily than
CER. LinTO/Vosk is therefore accepted for the desktop proof of concept, not as
a production-quality recognition claim. Broader speakers, environments,
French vocabulary, memory use, and a native mobile host remain acceptance
work.
