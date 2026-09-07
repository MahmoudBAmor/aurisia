---
license: other
license_name: audarai-open-license-v1.0
license_link: https://www.audarai.com/license/audarai-open-license-v1.0/
language:
- ar
- en
pipeline_tag: automatic-speech-recognition
library_name: transformers
inference: false
tags:
- automatic-speech-recognition
- asr
- speech-recognition
- arabic
- arabic-asr
- dialectal-arabic
- emirati
- gulf-arabic
- streaming
- realtime
- gguf
- llama-cpp
- on-device
- edge
- audar
---

<div align="center">

# Audar-ASR-V1-Flash · Transformers + GGUF

### Audar's Arabic-first ASR — the real-time, edge tier.

**From Arabic to the world.**

![License](https://img.shields.io/badge/license-AudarAI%20Open%20v1.0-6f42c1)
![Task](https://img.shields.io/badge/task-ASR-blue)
![Format](https://img.shields.io/badge/format-Transformers%20%2B%20GGUF-blue)
![Params](https://img.shields.io/badge/params-0.78B%20total-f59e0b)
![Open-AR-ASR](https://img.shields.io/badge/Open--AR--ASR-32.0%25%20avg%20WER-brightgreen)
![Languages](https://img.shields.io/badge/languages-30%20(Arabic%20%2B%20English%20%2B%2028)-f59e0b)
![Runs on](https://img.shields.io/badge/runs%20on-CPU%20%7C%20GPU%20%7C%20edge-informational)
[![GitHub](https://img.shields.io/badge/GitHub-Audar--ASR--V1-181717?logo=github)](https://github.com/AudarAI/Audar-ASR-V1)

<p><a href="#-what-it-is"><b>🧭 Overview</b></a> · <a href="#-benchmarks"><b>📊 Benchmarks</b></a> · <a href="#-transformers-inference"><b>🤗 Transformers</b></a> · <a href="#-gguf-inference-llamacpp"><b>💻 GGUF</b></a> · <a href="#-real-time-streaming"><b>🎙️ Streaming</b></a> · <a href="https://github.com/AudarAI/Audar-ASR-V1/blob/main/report/Audar-ASR-V1-Technical-Report.pdf"><b>📄 Tech Report</b></a> · <a href="#-vllm-inference-gpu-serving"><b>⚡ vLLM</b></a> · <a href="https://github.com/AudarAI/Audar-ASR-V1"><b>🐙 GitHub</b></a> · <a href="https://www.audarai.com"><b>☁️ Audar API</b></a> · <a href="https://www.audarai.com/license/audarai-open-license-v1.0/"><b>📜 License</b></a></p>

</div>

---

## 🧭 What it is

**Audar-ASR-V1-Flash** is the **edge tier** of **Audar's Arabic-first speech-recognition family** —
the same in-house Arabic training program as [Audar-ASR-V1-Turbo](https://huggingface.co/audarai/Audar-ASR-V1-Turbo),
delivered in a fast ~0.6B-decoder model for **real-time captioning and on-device use**. It recasts
transcription as **audio-conditioned next-token prediction** (a language-model decoder, not CTC/transducer),
and is built on a permissively-licensed open-weight audio-LLM foundation, then adapted in-house through Audar's Arabic training program — the contribution is the adaptation, not the foundation:

- 🧱 **Large-scale bilingual pretraining** — 300,000+ hours of labeled audio, primarily Arabic and English (MSA + Gulf, Egyptian,
  Levantine, Maghrebi; code-switching; diverse channels).
- 🎯 **Dialect-targeted fine-tuning** with hardness and multi-task sampling.
- 🧠 **KTO preference alignment** (Kahneman-Tversky Optimization) from trained native-Arabic annotators.

It transcribes MSA and every major Arabic dialect, code-switched Arabic–English, and English, across
**30 languages**, and runs on **CPU / GPU / edge** via 🤗 Transformers or GGUF. For maximum accuracy on
the hardest dialectal audio, use the larger **Turbo** tier.

> Built on a **permissively-licensed open-weight audio-LLM foundation**; the adaptation, data, and
> alignment are Audar's. Full method and results: [Audar-ASR-V1 Technical Report](https://github.com/AudarAI/Audar-ASR-V1/blob/main/report/Audar-ASR-V1-Technical-Report.pdf). Runs via Transformers, llama.cpp / GGUF, and vLLM.

## Model summary

<table>
<tbody>
<tr><td width="200"><b>Model</b></td><td>Audar-ASR-V1-Flash — Arabic-first generative ASR (edge tier)</td></tr>
<tr><td><b>Task</b></td><td>Automatic speech recognition (audio → text)</td></tr>
<tr><td><b>Approach</b></td><td>Generative ASR — audio encoder + language-model decoder</td></tr>
<tr><td><b>Training</b></td><td>built on an open-weight audio-LLM foundation; adapted via a curriculum — 300k+ hrs bilingual pretraining → dialect-targeted SFT → KTO alignment</td></tr>
<tr><td><b>Decoder parameters</b></td><td>596,049,920 (0.60B)</td></tr>
<tr><td><b>Audio encoder parameters</b></td><td>186,376,192 (0.19B)</td></tr>
<tr><td><b>Total parameters</b></td><td>782,426,112 (0.78B, bf16)</td></tr>
<tr><td><b>Audio input</b></td><td>16 kHz mono; 30 s context (longer audio is chunked/streamed)</td></tr>
<tr><td><b>Languages</b></td><td>Arabic (MSA + Gulf/Egyptian/Levantine/Maghrebi dialects) + English + 28 more</td></tr>
<tr><td><b>Runtimes</b></td><td>🤗 Transformers (GPU) · GGUF / llama.cpp (CPU · GPU · edge) · vLLM</td></tr>
<tr><td><b>License</b></td><td>AudarAI Open License v1.0</td></tr>
</tbody>
</table>

## 📊 Benchmarks

### Open Universal Arabic ASR Leaderboard — full standings

Flash is evaluated end-to-end on **all six** leaderboard test sets (full test splits, not sampled), with
the **leaderboard-equivalent normalizer** — the same harness and protocol as every other row (Audar rows below are the leaderboard
maintainers' independent reproduction, Aug 2026 normalization). **Audar-ASR-V1-Flash scores 32.0 avg WER
at just 0.78B parameters** — on par with Qwen3-ASR-1.7B (2× its size) and ahead of
Voxtral-Small-24B, Whisper-large-v3, and every CTC baseline.
Audar's accuracy tier, [**Turbo**](https://huggingface.co/audarai/Audar-ASR-V1-Turbo#-benchmarks), is **#1**.

*Per-dataset **WER %** across all six sets, plus the two composite averages. Lower is better; **Avg WER**
is the ranking metric. **Flash and Turbo (Ours) in bold**; **bold cell** = best in column.*

| # | Model | **Avg WER** | Avg CER | SADA | CV-18 | MASC-clean | MASC-noisy | MGB-2 | Casablanca |
| --: | --- | --: | --: | --: | --: | --: | --: | --: | --: |
| 1 | **Audar-ASR-V1-Turbo (Ours, 2.35B)** | **23.17** | **9.20** | **28.92** | 8.09 | **16.73** | 27.19 | **11.08** | **47.02** |
| 2 | CohereLabs/cohere-transcribe-arabic-07-2026 | 25.87 | 11.80 | 37.47 | **5.82** | 19.60 | 27.07 | 15.54 | **49.71** |
| 3 | omnilingual-asr/omniASR_LLM_7B | 28.32 | 12.52 | 41.61 | 8.75 | 19.69 | 29.29 | 14.13 | 56.46 |
| 4 | omnilingual-asr/omniASR_LLM_3B | 29.96 | 13.77 | 46.18 | 9.15 | 19.90 | 30.03 | 14.22 | 60.27 |
| 5 | omnilingual-asr/omniASR_LLM_1B | 29.96 | 13.40 | 43.84 | 9.55 | 20.03 | 30.26 | 15.34 | 60.68 |
| 6 | CohereLabs/cohere-transcribe-03-2026 | 30.67 | 16.37 | 60.11 | 8.17 | **8.66** | **19.01** | 25.33 | 62.71 |
| 7 | Qwen/Qwen3-Omni-30B-A3B-Instruct | 30.71 | 13.67 | 44.82 | 11.46 | 21.47 | 30.85 | 13.09 | 62.55 |
| **8** | **Audar-ASR-V1-Flash (Ours, 0.78B)** | **32.04** | 13.43 | 44.36 | 15.38 | 22.56 | 34.19 | 17.05 | 58.71 |
| 9 | nvidia-conformer-ctc-large-arabic (lm) | 32.91 | 13.84 | 44.52 | 8.80 | 23.74 | 34.29 | 17.20 | 68.90 |
| 10 | omnilingual-asr/omniASR_LLM_300M | 32.96 | 14.84 | 51.38 | 12.03 | 20.66 | 32.45 | 16.58 | 64.64 |
| 11 | google/gemma-4-E4B-it | 32.98 | 13.71 | 43.40 | 19.65 | 24.86 | 33.59 | 17.72 | 58.63 |
| 12 | Qwen/Qwen3-ASR-1.7B | 33.36 | 12.33 | 45.53 | 16.90 | 24.37 | 34.29 | 16.57 | 64.47 |
| 13 | mistralai/Voxtral-Small-24B-2507 | 34.47 | 15.29 | 50.82 | 15.25 | 23.96 | 34.43 | 16.03 | 66.30 |
| 14 | nvidia-conformer-ctc-large-arabic (greedy) | 34.74 | 13.37 | 47.26 | 10.60 | 24.12 | 35.64 | 19.69 | 71.13 |
| 15 | google/gemma-4-E2B-it | 35.87 | 15.34 | 46.23 | 23.76 | 27.47 | 36.15 | 20.72 | 60.87 |
| 16 | openai/whisper-large-v3 | 36.86 | 17.21 | 55.96 | 17.83 | 24.66 | 34.63 | 16.26 | 71.81 |
| 17 | omnilingual-asr/omniASR_CTC_3B | 37.78 | 19.79 | 69.85 | 14.19 | 21.48 | 34.60 | 18.96 | 67.58 |
| 18 | omnilingual-asr/omniASR_CTC_7B | 38.12 | 20.91 | 72.69 | 12.47 | 21.08 | 35.04 | 20.43 | 67.02 |
| 19 | facebook/seamless-m4t-v2-large | 38.16 | 17.03 | 62.52 | 21.70 | 25.04 | 33.24 | 20.23 | 66.25 |
| 20 | omnilingual-asr/omniASR_CTC_1B | 39.29 | 20.47 | 71.42 | 17.55 | 22.76 | 35.73 | 19.96 | 68.32 |
| 21 | openai/whisper-large-v3-turbo | 40.05 | 18.87 | 60.36 | 25.73 | 25.51 | 37.16 | 17.75 | 73.79 |
| 22 | openai/whisper-large-v2 | 40.20 | 19.55 | 57.46 | 21.77 | 27.25 | 38.55 | 25.17 | 71.01 |
| 23 | Qwen/Qwen3-ASR-0.6B | 42.19 | 16.23 | 53.75 | 28.28 | 31.34 | 42.63 | 25.45 | 71.68 |
| 24 | openai/whisper-large | 42.57 | 20.49 | 63.24 | 26.04 | 28.89 | 40.79 | 24.28 | 72.18 |
| 25 | mistralai/Voxtral-Mini-3B-2507 | 42.58 | 19.90 | 63.65 | 22.12 | 28.37 | 41.27 | 22.56 | 77.52 |
| 26 | asafaya/hubert-large-arabic-transcribe | 45.50 | 17.35 | 67.82 | 8.01 | 32.94 | 50.16 | 37.51 | 76.53 |
| 27 | openai/whisper-medium | 45.57 | 22.27 | 67.71 | 28.07 | 29.99 | 42.91 | 29.32 | 75.44 |
| 28 | nvidia-Parakeet-ctc-1.1b-concat | 46.54 | 23.88 | 70.70 | 26.34 | 30.49 | 45.95 | 24.94 | 80.80 |
| 29 | omnilingual-asr/omniASR_CTC_300M | 46.65 | 21.86 | 78.11 | 27.90 | 28.40 | 43.26 | 26.85 | 75.35 |
| 30 | nvidia-Parakeet-ctc-1.1b-universal | 51.96 | 25.19 | 73.58 | 40.01 | 36.16 | 50.03 | 30.68 | 81.30 |
| 31 | microsoft/VibeVoice-ASR | 52.99 | 28.95 | 69.83 | 44.25 | 32.95 | 52.43 | 25.10 | 93.37 |
| 32 | facebook/mms-1b-all | 54.54 | 21.45 | 77.48 | 26.52 | 38.82 | 57.33 | 39.16 | 87.95 |
| 33 | openai/whisper-small | 55.13 | 21.68 | 78.02 | 24.18 | 35.93 | 56.36 | 48.64 | 87.64 |
| 34 | whitefox123/w2v-bert-2.0-arabic-4 | 58.13 | 27.62 | 87.34 | 41.79 | 37.82 | 53.28 | 40.66 | 87.88 |
| 35 | jonatasgrosman/wav2vec2-large-xlsr-53-arabic | 60.98 | 25.61 | 86.82 | 23.00 | 42.75 | 64.27 | 56.29 | 92.72 |
| 36 | speechbrain/asr-wav2vec2-commonvoice-14-ar | 65.74 | 30.93 | 88.54 | 29.17 | 49.10 | 69.57 | 64.37 | 93.68 |

### Flash — per-dataset detail (full test sets)

*Both metrics, for the six leaderboard sets and the composite average.*

| Dataset | WER % | CER % |
|---|--:|--:|
| SADA | 44.36 | 23.57 |
| CommonVoice-18 | 15.38 | 4.91 |
| MASC-clean | 22.56 | 7.48 |
| MASC-noisy | 34.19 | 12.52 |
| MGB-2 | 17.05 | 7.97 |
| Casablanca | 58.71 | 24.14 |
| **Average (6-set)** | **32.04** | **13.43** |

> Use **Flash** for real-time and on-device transcription; step up to
> [**Turbo**](https://huggingface.co/audarai/Audar-ASR-V1-Turbo#-benchmarks) when you need the lowest
> error on heavy dialectal or long-form audio — Turbo is **#1 on the leaderboard (23.2 % avg WER)** and
> cuts Flash's average WER by ~8.9 pp, with the biggest gains on SADA (44.4→28.9) and MGB-2 (17.1→11.1).

## 🏁 Benchmark-parity inference (qwen-asr) — recommended

Our leaderboard numbers were produced with the [`qwen-asr`](https://pypi.org/project/qwen-asr/) package, which implements this model's I/O protocol natively — and were independently reproduced by the leaderboard maintainers with this exact code:

```python
# pip install qwen-asr torch
import torch
from qwen_asr import Qwen3ASRModel

model = Qwen3ASRModel.from_pretrained(
    "audarai/Audar-ASR-V1-Flash",
    dtype=torch.bfloat16, device_map="cuda:0",
    max_inference_batch_size=16, max_new_tokens=256,
)
results = model.transcribe(audio=["clip.wav"], language=["Arabic"])
print(results[0].text)
```

Protocol handling is **mandatory**, not optional:

- `language="Arabic"` makes the package prefill `language Arabic<asr_text>` into the prompt, so the model never free-runs language identification.
- The model's no-speech verdict (`language None<asr_text>`) is mapped to an empty transcript; without this, non-speech audio (music, silence) can produce repetition loops.
- `max_new_tokens=256` and bf16 are the exact decode settings behind our published numbers.

If you use raw `transformers` (below), you **must** strip the `language <Lang><asr_text>` output prefix yourself and expect degraded scores on non-speech-heavy data.

## 🤗 Transformers inference

Ships self-contained modeling code, so `trust_remote_code=True` is required.

```python
# pip install "transformers>=4.57" torch librosa
import re, torch, librosa
from transformers import AutoProcessor, AutoModelForCausalLM

repo = "audarai/Audar-ASR-V1-Flash"
proc  = AutoProcessor.from_pretrained(repo, trust_remote_code=True)
model = AutoModelForCausalLM.from_pretrained(
    repo, trust_remote_code=True, torch_dtype=torch.bfloat16, device_map="cuda:0",
).eval()

SYSTEM = "فرّغ الكلام العربي التالي."          # "Transcribe the following Arabic speech."
audio, _ = librosa.load("clip.wav", sr=16000, mono=True)

conv = [
    {"role": "system", "content": SYSTEM},
    {"role": "user",   "content": [{"type": "audio"}]},   # audio placeholder (a list, not "<audio>")
]
text   = proc.apply_chat_template(conv, tokenize=False, add_generation_prompt=True)
inputs = proc(text=text, audio=audio, sampling_rate=16000, return_tensors="pt").to(model.device)
inputs["input_features"] = inputs["input_features"].to(model.dtype)   # features are fp32 → cast to bf16

out = model.generate(**inputs, max_new_tokens=440, do_sample=False)
hyp = proc.batch_decode(out[:, inputs["input_ids"].shape[1]:], skip_special_tokens=True)[0]
print(re.sub(r"^\s*language\s+[A-Za-z]+\s*(?:<asr_text>)?\s*", "", hyp).strip())
```

- **Language steering**: the Arabic auto-dialect prompt above needs no dialect hint. For other
  languages use e.g. `"Transcribe the following speech."`.
- **Long audio (>30 s)**: split at ~30 s boundaries (see the streaming section).

## ⚡ vLLM inference (GPU serving)

Flash also serves on **[vLLM](https://github.com/vllm-project/vllm)** with an OpenAI-compatible API. vLLM
implements the **Qwen3-ASR architecture natively**, so it serves the repo's **bf16 `model.safetensors`
directly** — no conversion, lossless (FLEURS AR/EN CER ≈ 3.3 %).

### 1. Install (audio support required)

The stock vLLM image ships no audio codecs; add PyAV + librosa + soundfile:

```dockerfile
FROM vllm/vllm-openai:v0.24.0
RUN pip install --no-cache-dir av librosa soundfile
```

```bash
docker build -t vllm-audio:0.24.0 .
```

### 2. Serve

```bash
hf download audarai/Audar-ASR-V1-Flash --local-dir ./flash --exclude "*.gguf"

docker run -d --name audar-asr --gpus '"device=0"' \
  -v $PWD/flash:/model:ro -p 8000:8000 \
  vllm-audio:0.24.0 \
  --model /model --served-model-name audar-asr-v1-flash \
  --trust-remote-code --max-model-len 8192 --gpu-memory-utilization 0.3
```

vLLM auto-detects the model; ~1.6 GB weights fit on any ≥ 8 GB GPU.

### 3. Transcribe

Send 16 kHz mono audio as base64 `input_audio` with the Arabic system prompt, decode greedily
(`temperature: 0`). `POST /v1/audio/transcriptions` (multipart) or `/v1/chat/completions` both work:

```bash
curl -s http://localhost:8000/v1/audio/transcriptions \
  -F model=audar-asr-v1-flash -F file=@clip.wav -F temperature=0
```

> **Output note:** Flash prefixes raw output with a `language <Lang><asr_text>` tag — strip it
> client-side (same as the Transformers example above):
> `re.sub(r"^\s*language\s+[A-Za-z]+\s*(?:<asr_text>)?\s*", "", text).strip()`.

---

## 💻 GGUF inference (llama.cpp)

Audar-ASR runs on **llama.cpp** via the multimodal (`mtmd`) path: a quantized **decoder** GGUF plus a
**BF16 audio projector** (`mmproj`). Build a recent llama.cpp (with Qwen3-ASR support), then:

```bash
./llama-mtmd-cli \
  -m       Audar-ASR-V1-Flash-Q8_0.gguf \
  --mmproj mmproj-Audar-ASR-V1-Flash.gguf \
  --audio  clip.wav \
  -sys     "فرّغ الكلام العربي التالي." \
  --temp 0
```

> ⚠️ The **audio projector (`mmproj`) must stay BF16** — the encoder's `ClippableLinear` is numerically
> sensitive, so F16/Q8 measurably degrade quality. The **decoder** quantizes normally.

### GGUF variants

| File | Approx. size | Notes |
|---|---|---|
| `Audar-ASR-V1-Flash-Q4_K_M.gguf` | ~0.40 GB | Smallest; best for edge/offline |
| `Audar-ASR-V1-Flash-Q8_0.gguf` | ~0.64 GB | Near-lossless, CPU-friendly (recommended) |
| `Audar-ASR-V1-Flash.gguf` (BF16) | ~1.20 GB | Full precision decoder |
| `mmproj-Audar-ASR-V1-Flash.gguf` | ~0.38 GB | **BF16 audio encoder — required, keep BF16** |

Prefer a managed endpoint? The Audar-ASR family is also available via the
[**Audar API/SDK**](https://www.audarai.com) — streaming, speaker-attributed transcription, and
diarization, production-hosted.

## 🎙️ Real-time streaming

The 30 s-context model streams via **LocalAgreement-2**: as audio arrives, the trailing window is
re-decoded each hop and a word is **committed** only once two consecutive decodes agree on it — giving
stable, low-latency incremental output on **both** the Transformers and GGUF paths. Audar's production
realtime engine serves the same policy over an OpenAI-Realtime-compatible WebSocket with model-based
endpointing.

## 🌍 Languages, dialects & tasks

- **Primary**: Arabic — MSA and dialectal (Gulf/Emirati, Egyptian, Levantine, Maghrebi), plus
  **code-switched Arabic–English**; dialect-faithful orthography from audio alone.
- **Also**: English + 28 additional languages.
- **Task**: transcription (audio → UTF-8 text), prompt-steerable for language/formatting.

## Intended use & limitations

**Intended use.** Live captioning and subtitles, voice assistants/agents, meeting and call-center
transcription, media/broadcast, accessibility — cloud, on-prem, or offline/edge.

**Limitations.**
- **Maghrebi / Moroccan Darija (Casablanca)** is the hardest condition for all systems.
- Heavily code-switched telephony and low-SNR audio degrade accuracy relative to clean MSA.
- Long recordings can drift; chunk at sentence boundaries for best results.
- Not evaluated for, and must **not** be used for, covert speaker identification.

## 📜 License

Released under the **AudarAI Open License v1.0** — commercial use, redistribution, and
fine-tuning/quantization permitted; ship the license and keep notices. See
[audarai.com/license/audarai-open-license-v1.0](https://www.audarai.com/license/audarai-open-license-v1.0/).

## Citation

```bibtex
@misc{audar-asr-flash-2026,
  title  = {Audar-ASR-V1: A Multilingual, Arabic-First Generative Speech Recognition Foundation Model},
  author = {AudarAI},
  year   = {2026},
  note   = {Audar-ASR-V1-Flash},
  url    = {https://github.com/AudarAI/Audar-ASR-V1/blob/main/report/Audar-ASR-V1-Technical-Report.pdf}
}
```

---

## About AudarAI

<div align="center">

### Leading Arabic-First Multilingual Audio Intelligence

*AudarAI starts with Arabic — and expands to the world.*

</div>

We are building advanced multilingual audio intelligence that helps individuals, enterprises, and
governments communicate across languages, cultures, and borders. By combining Arabic-first speech
technology with global multilingual AI, AudarAI transforms voice into understanding, interaction,
and connection.

Our work spans speech recognition, speech understanding, voice-enabled digital assistants,
human-computer interaction, and intelligent audio systems designed for real-world impact. From
empowering people to access technology in their native language to helping organizations
communicate globally, AudarAI is shaping a future where every voice can be heard, understood, and
connected.

**Arabic-first. Multilingual by design. Human-centered at heart.**

<div align="center">

**[🌐 www.audarai.com](https://www.audarai.com)** · [🤗 Hugging Face](https://huggingface.co/audarai) · [GitHub](https://github.com/AudarAI/Audar-ASR-V1) · contact@audarai.com

© 2026 AUDARAI PTE. LTD. · Licensed under the AudarAI Open License v1.0

</div>
