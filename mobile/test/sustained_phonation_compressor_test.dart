import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/domain/speech_turn.dart';
import 'package:aurisia_mobile/features/transcription/infrastructure/audio/sustained_phonation_compressor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const sampleRateHz = 16000;
  final compressor = SustainedPhonationCompressor();

  test('shortens an unusually long stable vowel-like phonation', () {
    final turn = _turn(
      _withSilence(
        _sineWave(
          frequencyHz: 180,
          duration: const Duration(milliseconds: 1700),
        ),
      ),
    );

    final processed = compressor.process(turn);

    expect(processed, isNot(same(turn)));
    expect(
      processed.samples.length,
      lessThan(turn.samples.length - sampleRateHz ~/ 2),
    );
    expect(processed.id, turn.id);
    expect(processed.startedAt, turn.startedAt);
    expect(processed.endedAt, turn.endedAt);
    expect(turn.samples.length, 30400);
  });

  test('leaves an ordinary short vowel unchanged', () {
    final turn = _turn(
      _withSilence(
        _sineWave(
          frequencyHz: 180,
          duration: const Duration(milliseconds: 600),
        ),
      ),
    );

    final processed = compressor.process(turn);

    expect(processed, same(turn));
  });

  test('does not compress changing voiced frames as one sustained vowel', () {
    final samples = <double>[];
    for (var index = 0; index < 8; index += 1) {
      samples.addAll(
        _sineWave(
          frequencyHz: index.isEven ? 90 : 330,
          duration: const Duration(milliseconds: 180),
        ),
      );
    }
    final turn = _turn(Float32List.fromList(samples));

    final processed = compressor.process(turn);

    expect(processed, same(turn));
  });
}

SpeechTurn _turn(Float32List samples) {
  final startedAt = DateTime.utc(2026);
  return SpeechTurn(
    id: 'turn-1',
    streamId: 'stream-1',
    startedAt: startedAt,
    endedAt: startedAt.add(
      Duration(microseconds: samples.length * 1000000 ~/ 16000),
    ),
    sampleRateHz: 16000,
    channels: 1,
    samples: samples,
  );
}

Float32List _sineWave({
  required double frequencyHz,
  required Duration duration,
  double amplitude = 0.4,
}) {
  final length = duration.inMicroseconds * 16000 ~/ 1000000;
  return Float32List.fromList(
    List<double>.generate(
      length,
      (index) =>
          amplitude * math.sin(2 * math.pi * frequencyHz * index / 16000),
    ),
  );
}

Float32List _withSilence(Float32List center) {
  const padding = 1600;
  return Float32List.fromList(<double>[
    ...Float32List(padding),
    ...center,
    ...Float32List(padding),
  ]);
}
