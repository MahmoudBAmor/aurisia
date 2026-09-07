import 'dart:typed_data';

Float32List pcm16LeBytesToFloat32(Uint8List bytes) {
  if (bytes.length.isOdd) {
    throw ArgumentError.value(bytes.length, 'bytes.length', 'must be even');
  }

  final data = ByteData.sublistView(bytes);
  final samples = Float32List(bytes.length ~/ 2);
  for (var index = 0; index < samples.length; index += 1) {
    samples[index] = data.getInt16(index * 2, Endian.little) / 32768.0;
  }
  return samples;
}

Uint8List float32ToPcm16LeBytes(Float32List samples) {
  final bytes = Uint8List(samples.length * 2);
  final data = ByteData.sublistView(bytes);
  for (var index = 0; index < samples.length; index += 1) {
    final sample = samples[index].clamp(-1.0, 1.0);
    final scaled = sample < 0
        ? (sample * 32768).round()
        : (sample * 32767).round();
    data.setInt16(index * 2, scaled, Endian.little);
  }
  return bytes;
}
