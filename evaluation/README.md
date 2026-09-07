# Local Tunisian ASR evaluation

This directory versions text manifests only. Private voice recordings and
reports belong under `recordings/` and must not be committed.

## Corpus contract

Each strict YAML manifest declares:

- a stable corpus id, version, locale, and display mode;
- a stable case id used as the local WAV filename;
- the Arabizi prompt shown to the speaker;
- the Arabic-script scoring reference;
- equivalent Arabic, French, or Arabizi spellings for code-switched terms.

Prompt text and scoring text are separate so display spelling can be corrected
without renaming an existing recording. Changes that alter the phrase itself
require a new corpus version and new recordings.

The initial Arabic references are provisional. A fluent Tunisian reviewer
should approve them before results are used as a model acceptance gate.

## Recording behavior

Recording is deliberately unavailable in normal live mode. The explicit CLI
workflow:

1. shows the exact local output directory;
2. requires the operator to type `RECORD`;
3. waits for confirmation before each phrase;
4. normalizes native capture to 16 kHz mono PCM;
5. uses the configured VAD and pre-roll to delimit one utterance;
6. writes each WAV atomically;
7. skips existing files unless `--overwrite-recordings` is explicitly passed.

The default maximum listening time is 12 seconds per phrase. Use
`--recording-timeout-seconds` with a value from 2 to 30 seconds when needed.

## Metrics

Evaluation keeps one recognizer loaded for the whole corpus and reports:

- word error rate (WER);
- character error rate (CER);
- code-switch term retention;
- total recognition work, finalization latency, and real-time factor;
- raw model output and normalized display output.

WER and CER use Unicode normalization, ignore case, punctuation, diacritics,
tatweel, and whitespace differences, but do not silently rewrite Tunisian
words. Code-switch aliases support common attached Arabic clitics.

The evaluator replays each WAV as ordered 20 ms frames. Total recognition time
covers all CPU work while finalization latency covers only the work remaining
after the last frame. Both intentionally exclude microphone capture and VAD
endpointing. In live mode, perceived post-speech latency is approximately the
configured VAD endpoint plus the `finalize` value printed by `--asr-metrics`.
