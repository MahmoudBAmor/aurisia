import '../speaker_attribution.dart';
import '../speech_turn.dart';

abstract interface class SpeakerAttributionEngine {
  Future<SpeakerAttribution> attribute(SpeechTurn turn);

  Future<void> reset();

  Future<void> close();
}
