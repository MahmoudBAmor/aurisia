import '../speech_turn.dart';

/// Transforms a completed speech turn before one ASR engine consumes it.
///
/// Implementations must not mutate [SpeechTurn.samples]. Keeping this as a
/// port lets a profile add domain-specific audio conditioning without coupling
/// the session or recognizer to a DSP implementation.
abstract interface class SpeechTurnPreprocessor {
  SpeechTurn process(SpeechTurn turn);
}
