import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../core/theme/app_theme.dart';
import '../features/transcription/domain/ports/transcription_session.dart';
import '../features/transcription/domain/transcription_profile.dart';
import 'aurisia_app.dart';

typedef TranscriptionSessionLoader = Future<TranscriptionSession> Function(
  TranscriptionProfile profile,
);

class AurisiaBootstrapApp extends StatefulWidget {
  const AurisiaBootstrapApp({
    required this.loadSession,
    required this.isDemo,
    this.initialProfile = TranscriptionProfile.tunisianConversation,
    super.key,
  });

  final TranscriptionSessionLoader loadSession;
  final bool isDemo;
  final TranscriptionProfile initialProfile;

  @override
  State<AurisiaBootstrapApp> createState() => _AurisiaBootstrapAppState();
}

class _AurisiaBootstrapAppState extends State<AurisiaBootstrapApp> {
  TranscriptionSession? _session;
  Object? _error;
  late TranscriptionProfile _profile;
  var _loading = true;
  var _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _profile = widget.initialProfile;
    _startLoad(notify: false);
  }

  void _startLoad({TranscriptionSession? previousSession, bool notify = true}) {
    final generation = ++_loadGeneration;
    void updateState() {
      _session = null;
      _error = null;
      _loading = true;
    }

    if (notify) {
      setState(updateState);
    } else {
      updateState();
    }
    unawaited(_load(generation, previousSession));
  }

  Future<void> _load(
    int generation,
    TranscriptionSession? previousSession,
  ) async {
    try {
      await previousSession?.close();
      final loaded = await widget.loadSession(_profile);
      if (!mounted || generation != _loadGeneration) {
        await loaded.close();
        return;
      }
      setState(() {
        _session = loaded;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _selectProfile(TranscriptionProfile profile) {
    if (_loading || profile == _profile) {
      return;
    }
    final previous = _session;
    _profile = profile;
    _startLoad(previousSession: previous);
  }

  void _retry() {
    if (!_loading) {
      _startLoad();
    }
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    unawaited(_session?.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session != null) {
      return AurisiaApp(
        key: ValueKey(_profile),
        session: session,
        profile: _profile,
        onProfileSelected: _selectProfile,
        isDemo: widget.isDemo,
      );
    }
    return MaterialApp(
      title: 'Aurisia',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar', 'TN'),
      supportedLocales: const [Locale('ar', 'TN')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: buildAurisiaTheme(),
      home: AurisiaSystemUi(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SafeArea(
              child: Center(
                child: _error != null
                    ? _StartupError(error: _error!, onRetry: _retry)
                    : const _InstallingModels(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _InstallingModels extends StatelessWidget {
  const _InstallingModels();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(),
          SizedBox(height: 22),
          Text(
            'نحضّر في نماذج النسخ...',
            key: Key('model-installation-status'),
            textAlign: TextAlign.center,
          ),
          SizedBox(height: 7),
          Text(
            'أول تشغيل ينجم ياخو شوية وقت، وبعد يخدم دون إنترنت',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.error_outline_rounded,
            color: AppColors.error,
            size: 48,
          ),
          const SizedBox(height: 14),
          const Text('ما نجّمنيش نحضّر نماذج النسخ'),
          const SizedBox(height: 7),
          Text(
            error.toString(),
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            key: const Key('retry-model-installation-button'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('عاود جرّب'),
          ),
        ],
      ),
    );
  }
}
