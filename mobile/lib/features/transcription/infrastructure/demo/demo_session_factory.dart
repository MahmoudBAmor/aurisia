import '../../application/default_transcription_session.dart';
import '../../domain/ports/transcription_session.dart';
import 'demo_speaker_attribution_engine.dart';
import 'demo_speech_turn_source.dart';
import 'demo_transcription_engine.dart';

TranscriptionSession createDemoTranscriptionSession() {
  return DefaultTranscriptionSession(
    source: DemoSpeechTurnSource(),
    transcriptionEngine: DemoTranscriptionEngine(),
    speakerEngine: DemoSpeakerAttributionEngine(),
  );
}
