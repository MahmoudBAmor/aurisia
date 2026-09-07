import 'dart:developer' as developer;

import '../domain/ports/speech_turn_preprocessor.dart';
import '../domain/ports/transcription_engine.dart';
import '../domain/speech_turn.dart';
import '../domain/transcript_hypothesis.dart';

/// Decorates one replaceable ASR engine with one replaceable audio transform.
class PreprocessingTranscriptionEngine implements TranscriptionEngine {
  const PreprocessingTranscriptionEngine({
    required this.engine,
    required this.preprocessor,
  });

  final TranscriptionEngine engine;
  final SpeechTurnPreprocessor preprocessor;

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) {
    final processed = preprocessor.process(turn);
    if (processed.samples.length != turn.samples.length) {
      final originalMilliseconds = _durationMilliseconds(turn);
      final processedMilliseconds = _durationMilliseconds(processed);
      developer.log(
        'audio_ms=$originalMilliseconds processed_audio_ms='
        '$processedMilliseconds duration_delta_ms='
        '${processedMilliseconds - originalMilliseconds}',
        name: 'aurisia.audio_preprocessing',
      );
    }
    return engine.transcribe(processed);
  }

  int _durationMilliseconds(SpeechTurn turn) {
    return (turn.samples.length * 1000 / turn.sampleRateHz / turn.channels)
        .round();
  }

  @override
  Future<void> close() => engine.close();
}
