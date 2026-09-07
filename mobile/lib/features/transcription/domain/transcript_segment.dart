import 'model_descriptor.dart';

class TranscriptSegment {
  const TranscriptSegment({
    required this.eventId,
    required this.streamId,
    required this.speakerId,
    required this.speakerIndex,
    required this.rawText,
    required this.displayText,
    required this.locale,
    required this.startedAt,
    required this.endedAt,
    required this.model,
    required this.isFinal,
    this.transcriptConfidence,
    this.speakerConfidence,
  });

  final String eventId;
  final String streamId;
  final String speakerId;
  final int speakerIndex;
  final String rawText;
  final String displayText;
  final String locale;
  final DateTime startedAt;
  final DateTime endedAt;
  final ModelDescriptor model;
  final bool isFinal;
  final double? transcriptConfidence;
  final double? speakerConfidence;
}
