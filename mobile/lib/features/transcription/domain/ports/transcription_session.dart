import '../transcript_segment.dart';

abstract interface class TranscriptionSession {
  Stream<TranscriptSegment> start();

  Future<void> stop();

  Future<void> close();
}
