import 'dart:typed_data';

import '../../domain/ports/speech_turn_preprocessor.dart';
import '../../domain/speech_turn.dart';

/// Appends decoder-only silence without changing captured timestamps.
///
/// Some encoder-decoder ASR models need a small acoustic tail to emit the last
/// spoken token. The original turn remains untouched, and streaming ASR plus
/// speaker attribution continue to consume the captured waveform.
class TrailingSilencePadder implements SpeechTurnPreprocessor {
  TrailingSilencePadder({required this.duration}) {
    if (duration.isNegative) {
      throw ArgumentError.value(duration, 'duration', 'must not be negative');
    }
  }

  final Duration duration;

  @override
  SpeechTurn process(SpeechTurn turn) {
    final paddingLength =
        (turn.sampleRateHz *
                duration.inMicroseconds /
                Duration.microsecondsPerSecond)
            .round();
    if (paddingLength == 0) {
      return turn;
    }
    final padded = Float32List(turn.samples.length + paddingLength)
      ..setRange(0, turn.samples.length, turn.samples);
    return SpeechTurn(
      id: turn.id,
      streamId: turn.streamId,
      startedAt: turn.startedAt,
      endedAt: turn.endedAt,
      sampleRateHz: turn.sampleRateHz,
      channels: turn.channels,
      samples: padded,
    );
  }
}
