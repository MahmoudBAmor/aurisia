import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'app/aurisia_bootstrap_app.dart';
import 'core/model_packs/bundled_model_pack.dart';
import 'core/model_packs/model_pack_materializer.dart';
import 'features/transcription/application/live_transcription_composition.dart';
import 'features/transcription/application/live_transcription_profile.dart';
import 'features/transcription/domain/ports/transcription_session.dart';
import 'features/transcription/domain/transcription_profile.dart';
import 'features/transcription/infrastructure/demo/demo_session_factory.dart';

const bool _demoMode = bool.fromEnvironment('AURISIA_DEMO');
const String _androidVoskPackRoot = 'assets/model_packs/aeb-TN-vosk-full';
const String _formalArabicPackRoot = 'assets/model_packs/ar-MGB2-vosk';
const String _multilingualRefinerPackRoot =
    'assets/model_packs/qwen3-asr-0.6B-int8';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(AurisiaBootstrapApp(loadSession: _loadSession, isDemo: _demoMode));
}

Future<TranscriptionSession> _loadSession(TranscriptionProfile profile) async {
  if (_demoMode) {
    return createDemoTranscriptionSession();
  }
  if (defaultTargetPlatform != TargetPlatform.android) {
    throw UnsupportedError(
      'Live offline transcription is currently packaged for Android ARM64.',
    );
  }

  final repository = BundledModelPackRepository();
  const materializer = NativeModelPackMaterializer();
  final primaryPack = await repository.load(
    assetRoot: switch (profile) {
      TranscriptionProfile.tunisianConversation => _androidVoskPackRoot,
      TranscriptionProfile.formalArabic => _formalArabicPackRoot,
    },
  );
  final refinerPack = profile == TranscriptionProfile.formalArabic
      ? await repository.load(assetRoot: _multilingualRefinerPackRoot)
      : null;
  final primaryPaths = await materializer.materialize(primaryPack);
  final refinerPaths = refinerPack == null
      ? const <String, String>{}
      : await materializer.materialize(refinerPack);
  final installedPaths = <String, String>{...primaryPaths, ...refinerPaths};
  return createLiveTranscriptionSession(
    models: LiveModelPaths.fromRolePaths(
      installedPaths,
      packId: primaryPack.packId,
      packVersion: primaryPack.version,
      locale: primaryPack.locale,
      runtime: primaryPack.runtime,
      finalPackId: refinerPack?.packId ?? '',
      finalPackVersion: refinerPack?.version ?? '',
      finalRuntime: refinerPack?.runtime ?? '',
    ),
    profile: LiveTranscriptionProfile.forId(profile),
  );
}
