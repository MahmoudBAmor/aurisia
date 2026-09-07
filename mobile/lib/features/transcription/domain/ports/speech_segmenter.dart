import '../pcm_audio_frame.dart';
import '../speech_turn.dart';

abstract interface class SpeechSegmenter {
  /// Accepts one chronological PCM frame and returns any turns completed by it.
  Iterable<SpeechTurn> acceptFrame(PcmAudioFrame frame);

  /// Completes the current turn after the audio source stops.
  Iterable<SpeechTurn> flush();

  Future<void> reset();

  Future<void> close();
}
