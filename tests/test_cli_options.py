from __future__ import annotations

import unittest
from pathlib import Path

from aurisia.apps.desktop.main import build_parser as build_desktop_parser
from aurisia.cli import build_parser as build_cli_parser


class AudioOverrideOptionTests(unittest.TestCase):
    def test_cli_accepts_native_capture_format_overrides(self) -> None:
        args = build_cli_parser().parse_args(
            [
                "--probe-microphone",
                "3",
                "--device",
                "12",
                "--sample-rate-hz",
                "48000",
                "--channels",
                "2",
            ]
        )

        self.assertEqual(args.device, "12")
        self.assertEqual(args.sample_rate_hz, 48_000)
        self.assertEqual(args.channels, 2)

    def test_desktop_accepts_native_capture_format_overrides(self) -> None:
        args = build_desktop_parser().parse_args(
            [
                "--live",
                "--device",
                "12",
                "--sample-rate-hz",
                "48000",
                "--channels",
                "2",
            ]
        )

        self.assertEqual(args.device, "12")
        self.assertEqual(args.sample_rate_hz, 48_000)
        self.assertEqual(args.channels, 2)

    def test_cli_accepts_bounded_vad_benchmark_mode(self) -> None:
        args = build_cli_parser().parse_args(["--benchmark-vad", "5"])

        self.assertEqual(args.benchmark_vad, 5.0)

    def test_live_launchers_accept_asr_metrics(self) -> None:
        cli_args = build_cli_parser().parse_args(["--live", "--asr-metrics"])
        desktop_args = build_desktop_parser().parse_args(["--live", "--asr-metrics"])

        self.assertTrue(cli_args.asr_metrics)
        self.assertTrue(desktop_args.asr_metrics)

    def test_cli_accepts_explicit_asr_corpus_workflows(self) -> None:
        record_args = build_cli_parser().parse_args(
            [
                "--record-asr-corpus",
                "evaluation/corpus.yaml",
                "--recording-timeout-seconds",
                "10",
            ]
        )
        evaluate_args = build_cli_parser().parse_args(
            [
                "--evaluate-asr-corpus",
                "evaluation/corpus.yaml",
                "--asr-report",
                "recordings/report.json",
            ]
        )

        self.assertEqual(
            record_args.record_asr_corpus,
            Path("evaluation/corpus.yaml"),
        )
        self.assertEqual(record_args.recording_timeout_seconds, 10.0)
        self.assertEqual(evaluate_args.asr_report, Path("recordings/report.json"))


if __name__ == "__main__":
    unittest.main()
