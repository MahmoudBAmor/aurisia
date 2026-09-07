import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/infrastructure/audio/pcm_conversion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('converts little-endian signed PCM16 to normalized float samples', () {
    final bytes = Uint8List.fromList([0x00, 0x80, 0x00, 0x00, 0xff, 0x7f]);

    final samples = pcm16LeBytesToFloat32(bytes);

    expect(samples[0], -1);
    expect(samples[1], 0);
    expect(samples[2], closeTo(0.99997, 0.00001));
  });

  test('rejects an incomplete PCM16 sample', () {
    expect(
      () => pcm16LeBytesToFloat32(Uint8List.fromList([1])),
      throwsArgumentError,
    );
  });

  test('converts normalized floats to little-endian signed PCM16', () {
    final bytes = float32ToPcm16LeBytes(
      Float32List.fromList([-1, -0.5, 0, 0.5, 1]),
    );
    final data = ByteData.sublistView(bytes);

    expect(data.getInt16(0, Endian.little), -32768);
    expect(data.getInt16(2, Endian.little), -16384);
    expect(data.getInt16(4, Endian.little), 0);
    expect(data.getInt16(6, Endian.little), 16384);
    expect(data.getInt16(8, Endian.little), 32767);
  });

  test('clips float samples before PCM16 conversion', () {
    final bytes = float32ToPcm16LeBytes(Float32List.fromList([-2, 2]));
    final data = ByteData.sublistView(bytes);

    expect(data.getInt16(0, Endian.little), -32768);
    expect(data.getInt16(2, Endian.little), 32767);
  });
}
