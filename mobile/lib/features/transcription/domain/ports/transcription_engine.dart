import '../pcm_audio_frame.dart';
import '../speech_turn.dart';
import '../transcript_hypothesis.dart';

abstract interface class TranscriptionEngine {
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn);

  Future<void> close();
}

/// Incremental ASR capability for engines that can decode live PCM.
///
/// Keeping this separate from [TranscriptionEngine.transcribe] lets the
/// application select streaming when available while retaining a portable
/// turn-based fallback for other runtimes and evaluation tools.
abstract interface class StreamingTranscriptionEngine
    implements TranscriptionEngine {
  Future<void> startStream();

  Future<TranscriptHypothesis> acceptFrame(PcmAudioFrame frame);

  Future<TranscriptHypothesis> finishStream();
}
