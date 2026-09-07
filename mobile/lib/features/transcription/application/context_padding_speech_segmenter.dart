import 'dart:collection';
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/pcm_audio_frame.dart';
import '../domain/ports/speech_segmenter.dart';
import '../domain/speech_turn.dart';

/// Restores bounded microphone context around model-trimmed VAD turns.
///
/// The wrapped segmenter still owns speech detection and timing. This
/// decorator retains raw chronological PCM so downstream final ASR and speaker
/// adapters receive weak initial/final phonemes that the VAD may classify as
/// silence. It does not delay endpoint decisions.
class ContextPaddingSpeechSegmenter implements SpeechSegmenter {
  ContextPaddingSpeechSegmenter({
    required this.segmenter,
    required this.leadingPadding,
    required this.trailingPadding,
    required this.historyDuration,
  }) {
    if (leadingPadding.isNegative || trailingPadding.isNegative) {
      throw ArgumentError('Speech context padding cannot be negative.');
    }
    if (historyDuration <= leadingPadding + trailingPadding) {
      throw ArgumentError(
        'Speech context history must exceed the combined padding.',
      );
    }
  }

  final SpeechSegmenter segmenter;
  final Duration leadingPadding;
  final Duration trailingPadding;
  final Duration historyDuration;

  final ListQueue<_AudioChunk> _history = ListQueue<_AudioChunk>();
  DateTime? _streamEpoch;
  String? _streamId;
  int? _sampleRateHz;
  var _acceptedSamples = 0;

  @override
  Iterable<SpeechTurn> acceptFrame(PcmAudioFrame frame) {
    _initializeOrValidate(frame);
    _history.addLast(
      _AudioChunk(start: _acceptedSamples, samples: frame.samples),
    );
    _acceptedSamples += frame.samples.length ~/ frame.channels;
    final turns = segmenter
        .acceptFrame(frame)
        .map(_withContext)
        .toList(growable: false);
    _pruneHistory();
    return turns;
  }

  @override
  Iterable<SpeechTurn> flush() {
    final turns = segmenter.flush().map(_withContext).toList(growable: false);
    _pruneHistory();
    return turns;
  }

  SpeechTurn _withContext(SpeechTurn turn) {
    final epoch = _streamEpoch;
    final sampleRateHz = _sampleRateHz;
    if (epoch == null || sampleRateHz == null || turn.channels != 1) {
      return turn;
    }
    final turnStart = _sampleIndex(epoch, turn.startedAt, sampleRateHz);
    final turnEnd = turnStart + turn.samples.length;
    final desiredStart = math.max(
      0,
      turnStart - _durationSamples(leadingPadding, sampleRateHz),
    );
    final desiredEnd = math.min(
      _acceptedSamples,
      turnEnd + _durationSamples(trailingPadding, sampleRateHz),
    );
    final samples = _copyHistory(desiredStart, desiredEnd);
    if (samples == null || samples.isEmpty) {
      return turn;
    }
    return SpeechTurn(
      id: turn.id,
      streamId: turn.streamId,
      startedAt: epoch.add(_samplesDuration(desiredStart, sampleRateHz)),
      endedAt: epoch.add(_samplesDuration(desiredEnd, sampleRateHz)),
      sampleRateHz: turn.sampleRateHz,
      channels: turn.channels,
      samples: samples,
    );
  }

  Float32List? _copyHistory(int start, int end) {
    if (end <= start) {
      return null;
    }
    final output = Float32List(end - start);
    var copied = 0;
    for (final chunk in _history) {
      final overlapStart = math.max(start, chunk.start);
      final overlapEnd = math.min(end, chunk.end);
      if (overlapEnd <= overlapStart) {
        continue;
      }
      final count = overlapEnd - overlapStart;
      output.setRange(
        overlapStart - start,
        overlapEnd - start,
        chunk.samples,
        overlapStart - chunk.start,
      );
      copied += count;
    }
    return copied == output.length ? output : null;
  }

  void _initializeOrValidate(PcmAudioFrame frame) {
    if (frame.channels != 1) {
      throw ArgumentError(
        'Speech context padding requires mono PCM, got ${frame.channels}ch.',
      );
    }
    final streamId = _streamId;
    final sampleRateHz = _sampleRateHz;
    if (streamId == null) {
      _streamId = frame.streamId;
      _sampleRateHz = frame.sampleRateHz;
      _streamEpoch = frame.capturedAt.subtract(
        _samplesDuration(
          frame.samples.length ~/ frame.channels,
          frame.sampleRateHz,
        ),
      );
      return;
    }
    if (streamId != frame.streamId || sampleRateHz != frame.sampleRateHz) {
      throw StateError('The audio stream changed before VAD reset.');
    }
  }

  void _pruneHistory() {
    final sampleRateHz = _sampleRateHz;
    if (sampleRateHz == null) {
      return;
    }
    final cutoff =
        _acceptedSamples - _durationSamples(historyDuration, sampleRateHz);
    while (_history.isNotEmpty && _history.first.end <= cutoff) {
      _history.removeFirst();
    }
  }

  int _sampleIndex(DateTime epoch, DateTime time, int sampleRateHz) {
    return (time.difference(epoch).inMicroseconds *
            sampleRateHz /
            Duration.microsecondsPerSecond)
        .round();
  }

  int _durationSamples(Duration duration, int sampleRateHz) {
    return (duration.inMicroseconds *
            sampleRateHz /
            Duration.microsecondsPerSecond)
        .round();
  }

  Duration _samplesDuration(int samples, int sampleRateHz) {
    return Duration(
      microseconds: (samples * Duration.microsecondsPerSecond / sampleRateHz)
          .round(),
    );
  }

  @override
  Future<void> reset() async {
    _history.clear();
    _streamEpoch = null;
    _streamId = null;
    _sampleRateHz = null;
    _acceptedSamples = 0;
    await segmenter.reset();
  }

  @override
  Future<void> close() async {
    _history.clear();
    await segmenter.close();
  }
}

class _AudioChunk {
  const _AudioChunk({required this.start, required this.samples});

  final int start;
  final Float32List samples;

  int get end => start + samples.length;
}
