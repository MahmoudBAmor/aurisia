import 'package:aurisia_mobile/features/transcription/application/transcription_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transcription_session.dart';
import 'support/transcript_fixtures.dart';

void main() {
  test('updates a partial result in place and retains its speaker', () async {
    final session = FakeTranscriptionSession();
    final controller = TranscriptionController(session: session);
    await controller.start();

    session.emit(
      transcriptFixture(text: 'نحب نعمل', isFinal: false, speakerIndex: 2),
    );
    await Future<void>.delayed(Duration.zero);
    session.emit(
      transcriptFixture(
        text: 'نحب نعمل رونديفو غدوة',
        isFinal: true,
        speakerIndex: 2,
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(controller.segments, hasLength(1));
    expect(controller.segments.single.displayText, 'نحب نعمل رونديفو غدوة');
    expect(controller.segments.single.speakerIndex, 2);
    expect(controller.segments.single.isFinal, isTrue);

    await controller.stop();
    expect(session.stopped, isTrue);
    expect(controller.status, TranscriptionStatus.idle);
    controller.dispose();
  });

  test('surfaces session errors as a failed state', () async {
    final session = FakeTranscriptionSession();
    final controller = TranscriptionController(session: session);
    await controller.start();

    session.emitError(StateError('microphone unavailable'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.status, TranscriptionStatus.failed);
    expect(controller.error, isA<StateError>());
    controller.dispose();
  });
}
