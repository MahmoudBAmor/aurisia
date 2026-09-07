import 'dart:typed_data';

class SpeechTurn {
  SpeechTurn({
    required this.id,
    required this.streamId,
    required this.startedAt,
    required this.endedAt,
    required this.sampleRateHz,
    required this.channels,
    required Float32List samples,
  }) : samples = Float32List.fromList(samples) {
    if (id.isEmpty || streamId.isEmpty) {
      throw ArgumentError(
        'Speech turn and stream identifiers must not be empty.',
      );
    }
    if (sampleRateHz <= 0 || channels <= 0) {
      throw ArgumentError('Audio format values must be positive.');
    }
    if (endedAt.isBefore(startedAt)) {
      throw ArgumentError('Speech turn cannot end before it starts.');
    }
  }

  final String id;
  final String streamId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int sampleRateHz;
  final int channels;

  /// Normalized mono PCM. Adapters must treat this owned buffer as read-only.
  final Float32List samples;
}
