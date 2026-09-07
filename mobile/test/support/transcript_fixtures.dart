import 'package:aurisia_mobile/features/transcription/domain/model_descriptor.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcript_segment.dart';

const testModel = ModelDescriptor(
  id: 'test-model',
  version: '1.0.0',
  runtime: 'fake',
);

TranscriptSegment transcriptFixture({
  String eventId = 'event-1',
  int speakerIndex = 0,
  String text = 'عسلامة شنو حوالك؟',
  bool isFinal = true,
}) {
  final startedAt = DateTime.utc(2026, 1, 1, 12);
  return TranscriptSegment(
    eventId: eventId,
    streamId: 'test-stream',
    speakerId: 'speaker-$speakerIndex',
    speakerIndex: speakerIndex,
    rawText: text,
    displayText: text,
    locale: 'aeb-TN',
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(seconds: 1)),
    model: testModel,
    isFinal: isFinal,
    transcriptConfidence: 0.9,
    speakerConfidence: 0.8,
  );
}
