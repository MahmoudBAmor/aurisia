import 'dart:convert';
import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/infrastructure/audio/wave_encoding.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('encodes mono samples as a canonical PCM16 wave container', () {
    final wave = encodeMonoPcm16Wave(
      samples: Float32List.fromList(<double>[-1, 0, 1]),
      sampleRateHz: 16000,
    );
    final data = ByteData.sublistView(wave);

    expect(ascii.decode(wave.sublist(0, 4)), 'RIFF');
    expect(data.getUint32(4, Endian.little), 42);
    expect(ascii.decode(wave.sublist(8, 12)), 'WAVE');
    expect(ascii.decode(wave.sublist(12, 16)), 'fmt ');
    expect(data.getUint16(20, Endian.little), 1);
    expect(data.getUint16(22, Endian.little), 1);
    expect(data.getUint32(24, Endian.little), 16000);
    expect(data.getUint32(28, Endian.little), 32000);
    expect(data.getUint16(34, Endian.little), 16);
    expect(ascii.decode(wave.sublist(36, 40)), 'data');
    expect(data.getUint32(40, Endian.little), 6);
    expect(data.getInt16(44, Endian.little), -32768);
    expect(data.getInt16(46, Endian.little), 0);
    expect(data.getInt16(48, Endian.little), 32767);
  });

  test('rejects a non-positive sample rate', () {
    expect(
      () => encodeMonoPcm16Wave(samples: Float32List(0), sampleRateHz: 0),
      throwsArgumentError,
    );
  });
}
