import 'dart:async';

import 'package:aurisia_mobile/features/transcription/domain/ports/transcription_session.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcript_segment.dart';

class FakeTranscriptionSession implements TranscriptionSession {
  final StreamController<TranscriptSegment> _events =
      StreamController<TranscriptSegment>.broadcast();

  bool started = false;
  bool stopped = false;
  bool closed = false;

  void emit(TranscriptSegment segment) => _events.add(segment);

  void emitError(Object error) => _events.addError(error);

  @override
  Stream<TranscriptSegment> start() {
    started = true;
    stopped = false;
    return _events.stream;
  }

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> close() async {
    if (closed) {
      return;
    }
    closed = true;
    await _events.close();
  }
}
