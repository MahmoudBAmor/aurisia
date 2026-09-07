import 'dart:async';

import 'package:aurisia_mobile/app/aurisia_bootstrap_app.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcription_profile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_transcription_session.dart';

void main() {
  testWidgets('shows model preparation before opening the live interface', (
    tester,
  ) async {
    final ready = Completer<FakeTranscriptionSession>();
    await tester.pumpWidget(
      AurisiaBootstrapApp(loadSession: (_) => ready.future, isDemo: false),
    );

    expect(find.text('نحضّر في نماذج النسخ...'), findsOneWidget);

    ready.complete(FakeTranscriptionSession());
    await tester.pumpAndSettle();

    expect(find.text('النسخ المباشر'), findsOneWidget);
    expect(find.text('عرض تجريبي'), findsNothing);
  });

  testWidgets('offers a retry when model preparation fails', (tester) async {
    var attempts = 0;
    Future<FakeTranscriptionSession> load(_) async {
      attempts += 1;
      if (attempts == 1) {
        throw StateError('model unavailable');
      }
      return FakeTranscriptionSession();
    }

    await tester.pumpWidget(
      AurisiaBootstrapApp(loadSession: load, isDemo: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('ما نجّمنيش نحضّر نماذج النسخ'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retry-model-installation-button')));
    await tester.pumpAndSettle();

    expect(attempts, 2);
    expect(find.text('النسخ المباشر'), findsOneWidget);
  });

  testWidgets('replaces the offline session when the profile changes', (
    tester,
  ) async {
    final tunisian = FakeTranscriptionSession();
    final formalArabic = FakeTranscriptionSession();
    final requestedProfiles = <TranscriptionProfile>[];

    await tester.pumpWidget(
      AurisiaBootstrapApp(
        loadSession: (profile) async {
          requestedProfiles.add(profile);
          return switch (profile) {
            TranscriptionProfile.tunisianConversation => tunisian,
            TranscriptionProfile.formalArabic => formalArabic,
          };
        },
        isDemo: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('تونسي • دون إنترنت'), findsOneWidget);
    await tester.tap(find.byKey(const Key('transcription-profile-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('عربية فصحى').last);
    await tester.pumpAndSettle();

    expect(tunisian.closed, isTrue);
    expect(find.text('عربية فصحى • دون إنترنت'), findsOneWidget);
    expect(requestedProfiles, <TranscriptionProfile>[
      TranscriptionProfile.tunisianConversation,
      TranscriptionProfile.formalArabic,
    ]);
  });
}
