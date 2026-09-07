import '../../domain/ports/speaker_attribution_engine.dart';
import '../../domain/speaker_attribution.dart';
import '../../domain/speech_turn.dart';

class DemoSpeakerAttributionEngine implements SpeakerAttributionEngine {
  static const _speakerSequence = <int>[0, 1, 0, 2, 1, 0];

  @override
  Future<SpeakerAttribution> attribute(SpeechTurn turn) async {
    final sequence = int.parse(turn.id.substring(turn.id.lastIndexOf('-') + 1));
    final index = _speakerSequence[sequence % _speakerSequence.length];
    return SpeakerAttribution(
      speakerId: 'demo-speaker-$index',
      speakerIndex: index,
      confidence: 1,
    );
  }

  @override
  Future<void> reset() async {}

  @override
  Future<void> close() async {}
}
