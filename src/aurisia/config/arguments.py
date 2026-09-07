"""Shared command-line validators for configuration overrides."""

from __future__ import annotations

import argparse


def sample_rate_argument(value: str) -> int:
    return _bounded_integer(value, minimum=8_000, maximum=192_000, label="sample rate")


def channel_count_argument(value: str) -> int:
    return _bounded_integer(value, minimum=1, maximum=8, label="channel count")


def _bounded_integer(
    value: str,
    *,
    minimum: int,
    maximum: int,
    label: str,
) -> int:
    try:
        parsed = int(value)
    except ValueError as exc:
        raise argparse.ArgumentTypeError(f"{label} must be an integer") from exc
    if not minimum <= parsed <= maximum:
        raise argparse.ArgumentTypeError(f"{label} must be between {minimum} and {maximum}")
    return parsed
