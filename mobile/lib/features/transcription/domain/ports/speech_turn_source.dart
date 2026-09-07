import '../speech_turn.dart';

abstract interface class SpeechTurnSource {
  Stream<SpeechTurn> start();

  Future<void> stop();

  Future<void> close();
}
