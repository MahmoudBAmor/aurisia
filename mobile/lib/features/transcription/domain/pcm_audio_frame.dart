import 'dart:typed_data';

class PcmAudioFrame {
  PcmAudioFrame({
    required this.streamId,
    required this.sequence,
    required this.capturedAt,
    required this.sampleRateHz,
    required this.channels,
    required Float32List samples,
  }) : samples = Float32List.fromList(samples) {
    if (streamId.isEmpty) {
      throw ArgumentError.value(streamId, 'streamId', 'must not be empty');
    }
    if (sequence < 0 || sampleRateHz <= 0 || channels <= 0) {
      throw ArgumentError('Audio sequence and format values must be valid.');
    }
  }

  final String streamId;
  final int sequence;
  final DateTime capturedAt;
  final int sampleRateHz;
  final int channels;
  final Float32List samples;
}
