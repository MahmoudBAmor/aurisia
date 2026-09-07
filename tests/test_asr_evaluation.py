from __future__ import annotations

import struct
import tempfile
import unittest
import wave
from pathlib import Path

from aurisia.evaluation import (
    AsrCorpus,
    AsrEvaluationCase,
    CodeSwitchTerm,
    CorpusError,
    capture_speech_segment,
    evaluate_asr_corpus,
    load_asr_corpus,
)
from aurisia.language import ArabicScriptNormalizer
from aurisia.services.audio.adapters import SyntheticAudioSource
from aurisia.services.speech import SpeechRecognitionService
from aurisia.services.speech.adapters import ScriptedSpeechEngine
from aurisia.services.vad import VadService
from aurisia.services.vad.adapters import EnergyVadEngine


class AsrCorpusTests(unittest.TestCase):
    def test_checked_in_tunisian_corpus_is_strict_and_versioned(self) -> None:
        corpus = load_asr_corpus(
            Path("evaluation/corpora/aeb-TN-field-v0.1.yaml")
        )

        self.assertEqual(corpus.locale, "aeb-TN")
        self.assertEqual(corpus.display_mode, "arabic")
        self.assertEqual(len(corpus.cases), 12)
        self.assertEqual(corpus.cases[-1].case_id, "pharmacy_panadol")

    def test_unknown_manifest_key_is_rejected(self) -> None:
        manifest = """\
schema_version: 1
corpus_id: sample
version: "1"
locale: aeb-TN
display_mode: arabic
unknown: true
cases: []
"""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "corpus.yaml"
            path.write_text(manifest, encoding="utf-8")

            with self.assertRaisesRegex(CorpusError, "unknown"):
                load_asr_corpus(path)


class AsrRecordingTests(unittest.TestCase):
    def test_capture_uses_vad_endpoint_and_bounded_pre_roll(self) -> None:
        source = SyntheticAudioSource(
            [0, 0, 5_000, 5_000, 0, 0, 0],
            stream_id="recording",
        )
        vad = VadService(
            EnergyVadEngine(rms_threshold=2_500),
            start_threshold=0.5,
            end_threshold=0.35,
            end_silence_frames=2,
        )

        segment = capture_speech_segment(
            iter(source.frames()),
            vad,
            pre_roll_ms=40,
            timeout_ms=2_000,
            segment_id="case",
        )

        self.assertEqual(segment.segment_id, "case")
        self.assertEqual(segment.start_time_ms, 0)
        self.assertEqual(segment.end_time_ms, 100)
        self.assertEqual(len(segment.pcm_s16le), 16_000 * 2 // 10)

    def test_capture_fails_when_no_speech_is_detected(self) -> None:
        source = SyntheticAudioSource([0] * 10)
        vad = VadService(EnergyVadEngine())

        with self.assertRaisesRegex(RuntimeError, "no speech"):
            capture_speech_segment(
                iter(source.frames()),
                vad,
                pre_roll_ms=40,
                timeout_ms=200,
                segment_id="silence",
            )


class AsrEvaluationRunnerTests(unittest.TestCase):
    def test_report_contains_accuracy_latency_and_code_switch_retention(self) -> None:
        case = AsrEvaluationCase(
            case_id="pharmacy",
            prompt_arabizi="emchi lel pharmacie",
            reference_arabic="امشي للفارماسي",
            code_switch_terms=(CodeSwitchTerm(("فارماسي", "pharmacie")),),
        )
        corpus = AsrCorpus(
            corpus_id="test-corpus",
            version="1",
            locale="aeb-TN",
            display_mode="arabic",
            cases=(case,),
        )
        speech = SpeechRecognitionService(
            ScriptedSpeechEngine(["امشي للفارماسي"]),
            ArabicScriptNormalizer({}),
            locale="aeb-TN",
        )
        with tempfile.TemporaryDirectory() as directory:
            audio_directory = Path(directory)
            _write_wave(audio_directory / "pharmacy.wav")

            report = evaluate_asr_corpus(corpus, audio_directory, speech)

        self.assertEqual(report.model.model_id, "development.scripted-aeb-tn")
        self.assertEqual(report.word_error_rate, 0.0)
        self.assertEqual(report.character_error_rate, 0.0)
        self.assertEqual(report.code_switch_retention_rate, 1.0)
        self.assertGreaterEqual(report.mean_recognition_latency_ms, 0.0)
        self.assertGreaterEqual(report.mean_finalization_latency_ms, 0.0)
        self.assertEqual(report.to_dict()["schema_version"], 2)
        self.assertEqual(
            report.to_dict()["cases"][0]["raw_transcript"],
            "امشي للفارماسي",
        )


def _write_wave(path: Path) -> None:
    samples = [1_000] * 8_000
    with wave.open(str(path), "wb") as recording:
        recording.setnchannels(1)
        recording.setsampwidth(2)
        recording.setframerate(16_000)
        recording.writeframes(struct.pack(f"<{len(samples)}h", *samples))


if __name__ == "__main__":
    unittest.main()
