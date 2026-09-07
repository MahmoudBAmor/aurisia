import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme.dart';
import '../features/transcription/domain/ports/transcription_session.dart';
import '../features/transcription/domain/transcription_profile.dart';
import '../features/transcription/presentation/transcription_screen.dart';

class AurisiaApp extends StatelessWidget {
  const AurisiaApp({
    required this.session,
    this.profile = TranscriptionProfile.tunisianConversation,
    this.onProfileSelected,
    this.isDemo = false,
    super.key,
  });

  final TranscriptionSession session;
  final TranscriptionProfile profile;
  final ValueChanged<TranscriptionProfile>? onProfileSelected;
  final bool isDemo;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Aurisia',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'TN'),
      supportedLocales: const [Locale('ar', 'TN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAurisiaTheme(),
      home: AurisiaSystemUi(
        child: TranscriptionScreen(
          session: session,
          profile: profile,
          onProfileSelected: onProfileSelected,
          isDemo: isDemo,
        ),
      ),
    );
  }
}
