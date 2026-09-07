import 'package:aurisia_mobile/app/aurisia_app.dart';
import 'package:aurisia_mobile/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transcription_session.dart';
import 'support/transcript_fixtures.dart';

void main() {
  testWidgets(
    'renders RTL transcript cards with stable, distinct speaker cues',
    (tester) async {
      final session = FakeTranscriptionSession();
      await tester.pumpWidget(AurisiaApp(session: session));

      expect(find.text('النسخ المباشر'), findsOneWidget);
      expect(find.text('إضغط على الزر وابدأ أحكي'), findsOneWidget);
      expect(
        tester
            .widget<Directionality>(find.byType(Directionality).first)
            .textDirection,
        TextDirection.rtl,
      );

      await tester.tap(find.byKey(const Key('record-button')));
      await tester.pump();
      expect(session.started, isTrue);
      expect(find.text('نسمع فيك...'), findsOneWidget);

      session.emit(transcriptFixture(eventId: 'speaker-one', speakerIndex: 0));
      session.emit(
        transcriptFixture(
          eventId: 'speaker-two',
          speakerIndex: 1,
          text: 'الحمد لله لاباس',
        ),
      );
      await tester.pump();

      expect(find.text('المتحدث ١'), findsOneWidget);
      expect(find.text('المتحدث ٢'), findsOneWidget);
      expect(find.text('عسلامة شنو حوالك؟'), findsOneWidget);
      expect(find.text('الحمد لله لاباس'), findsOneWidget);

      final first = tester.widget<Container>(
        find.byKey(const ValueKey('speaker-one')),
      );
      final second = tester.widget<Container>(
        find.byKey(const ValueKey('speaker-two')),
      );
      final firstBorder =
          (first.decoration! as BoxDecoration).border! as Border;
      final secondBorder =
          (second.decoration! as BoxDecoration).border! as Border;
      expect(firstBorder.right.color, SpeakerColors.forIndex(0));
      expect(secondBorder.right.color, SpeakerColors.forIndex(1));
      expect(firstBorder.right.color, isNot(secondBorder.right.color));

      await tester.tap(find.byKey(const Key('clear-transcript-button')));
      await tester.pump();
      expect(find.text('إضغط على الزر وابدأ أحكي'), findsOneWidget);
    },
  );

  testWidgets('scrolls to the latest transcript as segments are appended', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(420, 620);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final session = FakeTranscriptionSession();
    await tester.pumpWidget(AurisiaApp(session: session));
    await tester.tap(find.byKey(const Key('record-button')));
    await tester.pump();

    for (var index = 0; index < 12; index += 1) {
      session.emit(
        transcriptFixture(
          eventId: 'segment-$index',
          speakerIndex: index % 3,
          text: 'هذا نص طويل للتأكد من النزول التلقائي عدد $index',
        ),
      );
    }
    await tester.pump();
    await tester.pumpAndSettle();

    final list = find.byKey(const Key('transcript-list'));
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    final position = tester.state<ScrollableState>(scrollable).position;
    expect(position.maxScrollExtent, greaterThan(0));
    expect(position.pixels, closeTo(position.maxScrollExtent, 0.5));
    expect(find.byKey(const ValueKey('segment-11')), findsOneWidget);
  });
}
