import 'dart:math' as math;
import 'dart:typed_data';

import '../../domain/ports/speech_turn_preprocessor.dart';
import '../../domain/speech_turn.dart';

/// Shortens only unusually long, stable voiced spans in expressive speech.
///
/// Preachers may sustain a vowel far beyond durations represented in general
/// ASR training data. This lightweight detector uses frame energy, zero-
/// crossing rate, and normalized waveform slope. It preserves the beginning
/// and end of the phonation and crossfades the join; normal vowels below
/// [minimumSustainedDuration] pass through unchanged.
class SustainedPhonationCompressor implements SpeechTurnPreprocessor {
  SustainedPhonationCompressor({
    this.minimumSustainedDuration = const Duration(milliseconds: 900),
    this.retainedDuration = const Duration(milliseconds: 560),
    this.analysisFrameDuration = const Duration(milliseconds: 20),
    this.minimumRms = 0.012,
    this.maximumRmsDeltaDb = 4,
    this.maximumZeroCrossingDelta = 0.018,
    this.maximumSlopeDelta = 0.1,
    this.maximumUnstableFrames = 2,
    this.crossfadeDuration = const Duration(milliseconds: 10),
  }) : assert(minimumSustainedDuration > retainedDuration),
       assert(analysisFrameDuration > Duration.zero),
       assert(minimumRms > 0),
       assert(maximumRmsDeltaDb > 0),
       assert(maximumZeroCrossingDelta > 0),
       assert(maximumSlopeDelta > 0),
       assert(maximumUnstableFrames >= 0),
       assert(crossfadeDuration >= Duration.zero);

  final Duration minimumSustainedDuration;
  final Duration retainedDuration;
  final Duration analysisFrameDuration;
  final double minimumRms;
  final double maximumRmsDeltaDb;
  final double maximumZeroCrossingDelta;
  final double maximumSlopeDelta;
  final int maximumUnstableFrames;
  final Duration crossfadeDuration;

  @override
  SpeechTurn process(SpeechTurn turn) {
    if (turn.channels != 1 || turn.samples.isEmpty) {
      return turn;
    }
    final frameSamples = _samplesFor(analysisFrameDuration, turn.sampleRateHz);
    final minimumRunSamples = _samplesFor(
      minimumSustainedDuration,
      turn.sampleRateHz,
    );
    final retainedSamples = _samplesFor(retainedDuration, turn.sampleRateHz);
    if (frameSamples < 2 || turn.samples.length < minimumRunSamples) {
      return turn;
    }

    final ranges = _findSustainedRanges(
      turn.samples,
      frameSamples: frameSamples,
      minimumRunSamples: minimumRunSamples,
    );
    if (ranges.isEmpty) {
      return turn;
    }
    final compressed = _compressRanges(
      turn.samples,
      ranges,
      retainedSamples: retainedSamples,
      crossfadeSamples: _samplesFor(crossfadeDuration, turn.sampleRateHz),
    );
    if (compressed.length == turn.samples.length) {
      return turn;
    }
    return SpeechTurn(
      id: turn.id,
      streamId: turn.streamId,
      startedAt: turn.startedAt,
      endedAt: turn.endedAt,
      sampleRateHz: turn.sampleRateHz,
      channels: turn.channels,
      samples: compressed,
    );
  }

  List<_SampleRange> _findSustainedRanges(
    Float32List samples, {
    required int frameSamples,
    required int minimumRunSamples,
  }) {
    final ranges = <_SampleRange>[];
    _FrameFeatures? anchor;
    int? runStart;
    var lastStableEnd = 0;
    var unstableFrames = 0;

    void finishRun() {
      final start = runStart;
      if (start != null && lastStableEnd - start >= minimumRunSamples) {
        ranges.add(_SampleRange(start, lastStableEnd));
      }
      runStart = null;
      anchor = null;
      unstableFrames = 0;
    }

    for (
      var offset = 0;
      offset + frameSamples <= samples.length;
      offset += frameSamples
    ) {
      final current = _features(samples, offset, frameSamples);
      final previous = anchor;
      if (previous != null && _isStableVoicing(previous, current)) {
        runStart ??= math.max(0, offset - frameSamples);
        lastStableEnd = offset + frameSamples;
        unstableFrames = 0;
        anchor = current;
        continue;
      }
      if (current.isVoiced && runStart == null) {
        anchor = current;
        continue;
      }
      if (runStart != null && unstableFrames < maximumUnstableFrames) {
        unstableFrames += 1;
        continue;
      }
      finishRun();
      if (current.isVoiced) {
        anchor = current;
      }
    }
    finishRun();
    return ranges;
  }

  _FrameFeatures _features(Float32List samples, int offset, int length) {
    var sumSquares = 0.0;
    var sumAbsolute = 0.0;
    var sumDelta = 0.0;
    var crossings = 0;
    var previous = samples[offset].toDouble();
    for (var index = offset; index < offset + length; index += 1) {
      final value = samples[index].toDouble();
      sumSquares += value * value;
      sumAbsolute += value.abs();
      if (index > offset) {
        sumDelta += (value - previous).abs();
        if ((value >= 0) != (previous >= 0)) {
          crossings += 1;
        }
      }
      previous = value;
    }
    final rms = math.sqrt(sumSquares / length);
    final zeroCrossingRate = crossings / (length - 1);
    final normalizedSlope = sumAbsolute <= 1e-9 ? 0.0 : sumDelta / sumAbsolute;
    final isVoiced =
        rms >= minimumRms &&
        zeroCrossingRate >= 0.004 &&
        zeroCrossingRate <= 0.12 &&
        normalizedSlope >= 0.015 &&
        normalizedSlope <= 0.75;
    return _FrameFeatures(
      rms: rms,
      zeroCrossingRate: zeroCrossingRate,
      normalizedSlope: normalizedSlope,
      isVoiced: isVoiced,
    );
  }

  bool _isStableVoicing(_FrameFeatures previous, _FrameFeatures current) {
    if (!previous.isVoiced || !current.isVoiced) {
      return false;
    }
    final rmsDeltaDb = (20 * _log10(current.rms / previous.rms)).abs();
    return rmsDeltaDb <= maximumRmsDeltaDb &&
        (current.zeroCrossingRate - previous.zeroCrossingRate).abs() <=
            maximumZeroCrossingDelta &&
        (current.normalizedSlope - previous.normalizedSlope).abs() <=
            maximumSlopeDelta;
  }

  Float32List _compressRanges(
    Float32List samples,
    List<_SampleRange> ranges, {
    required int retainedSamples,
    required int crossfadeSamples,
  }) {
    final output = <double>[];
    var cursor = 0;
    for (final range in ranges) {
      final extra = range.length - retainedSamples;
      if (extra <= 0) {
        continue;
      }
      final removalStart = range.start + retainedSamples ~/ 2;
      final removalEnd = math.min(range.end, removalStart + extra);
      output.addAll(samples.getRange(cursor, removalStart));
      final availableFade = math.min(
        crossfadeSamples,
        math.min(output.length, samples.length - removalEnd),
      );
      for (var index = 0; index < availableFade; index += 1) {
        final outputIndex = output.length - availableFade + index;
        final blend = (index + 1) / (availableFade + 1);
        output[outputIndex] =
            output[outputIndex] * (1 - blend) +
            samples[removalEnd + index] * blend;
      }
      cursor = removalEnd + availableFade;
    }
    output.addAll(samples.getRange(cursor, samples.length));
    return Float32List.fromList(output);
  }

  int _samplesFor(Duration duration, int sampleRateHz) {
    return (duration.inMicroseconds *
            sampleRateHz /
            Duration.microsecondsPerSecond)
        .round();
  }

  double _log10(double value) => math.log(value) / math.ln10;
}

class _FrameFeatures {
  const _FrameFeatures({
    required this.rms,
    required this.zeroCrossingRate,
    required this.normalizedSlope,
    required this.isVoiced,
  });

  final double rms;
  final double zeroCrossingRate;
  final double normalizedSlope;
  final bool isVoiced;
}

class _SampleRange {
  const _SampleRange(this.start, this.end);

  final int start;
  final int end;

  int get length => end - start;
}
