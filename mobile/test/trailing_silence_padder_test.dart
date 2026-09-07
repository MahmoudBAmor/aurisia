import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/domain/speech_turn.dart';
import 'package:aurisia_mobile/features/transcription/infrastructure/audio/trailing_silence_padder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('appends silence without changing captured audio or timestamps', () {
    final padder = TrailingSilencePadder(
      duration: const Duration(milliseconds: 500),
    );
    final startedAt = DateTime.utc(2026);
    final endedAt = startedAt.add(const Duration(milliseconds: 500));
    final turn = SpeechTurn(
      id: 'turn-1',
      streamId: 'stream-1',
      startedAt: startedAt,
      endedAt: endedAt,
      sampleRateHz: 4,
      channels: 1,
      samples: Float32List.fromList(<double>[0.25, -0.25]),
    );

    final padded = padder.process(turn);

    expect(turn.samples, <double>[0.25, -0.25]);
    expect(padded.samples, <double>[0.25, -0.25, 0, 0]);
    expect(padded.startedAt, startedAt);
    expect(padded.endedAt, endedAt);
  });
}
