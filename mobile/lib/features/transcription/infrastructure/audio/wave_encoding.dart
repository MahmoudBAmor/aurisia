import 'dart:convert';
import 'dart:typed_data';

import 'pcm_conversion.dart';

/// Encodes normalized mono samples as an uncompressed PCM16 WAV file.
///
/// The model boundary receives a complete media container instead of a
/// temporary file, so transcription remains offline and avoids filesystem
/// latency for every speech turn.
Uint8List encodeMonoPcm16Wave({
  required Float32List samples,
  required int sampleRateHz,
}) {
  if (sampleRateHz <= 0) {
    throw ArgumentError.value(sampleRateHz, 'sampleRateHz');
  }

  final pcm = float32ToPcm16LeBytes(samples);
  final bytes = Uint8List(44 + pcm.length);
  final header = ByteData.sublistView(bytes);

  void writeAscii(int offset, String value) {
    bytes.setRange(offset, offset + value.length, ascii.encode(value));
  }

  writeAscii(0, 'RIFF');
  header.setUint32(4, 36 + pcm.length, Endian.little);
  writeAscii(8, 'WAVE');
  writeAscii(12, 'fmt ');
  header
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little)
    ..setUint16(22, 1, Endian.little)
    ..setUint32(24, sampleRateHz, Endian.little)
    ..setUint32(28, sampleRateHz * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little);
  writeAscii(36, 'data');
  header.setUint32(40, pcm.length, Endian.little);
  bytes.setRange(44, bytes.length, pcm);
  return bytes;
}
