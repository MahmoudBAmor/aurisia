import '../domain/ports/pcm_audio_input.dart';
import '../domain/ports/speech_segmenter.dart';
import '../domain/ports/speech_turn_source.dart';
import '../domain/speech_turn.dart';

class SegmentedSpeechTurnSource implements SpeechTurnSource {
  SegmentedSpeechTurnSource({
    required this.audioInput,
    required this.segmenter,
  });

  final PcmAudioInput audioInput;
  final SpeechSegmenter segmenter;

  @override
  Stream<SpeechTurn> start() async* {
    await segmenter.reset();
    await for (final frame in audioInput.start()) {
      for (final turn in segmenter.acceptFrame(frame)) {
        yield turn;
      }
    }
    for (final turn in segmenter.flush()) {
      yield turn;
    }
  }

  @override
  Future<void> stop() => audioInput.stop();

  @override
  Future<void> close() async {
    await audioInput.close();
    await segmenter.close();
  }
}
