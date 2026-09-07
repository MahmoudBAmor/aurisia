import '../../domain/model_descriptor.dart';
import '../../domain/ports/transcription_engine.dart';
import '../../domain/speech_turn.dart';
import '../../domain/transcript_hypothesis.dart';

class DemoTranscriptionEngine implements TranscriptionEngine {
  static const _phrases = <String>[
    'عسلامة، شنو حوالك اليوم؟',
    'الحمد لله لاباس، وإنت شنو حوالك؟',
    'نحب نعمل رونديفو غدوة على العشرة.',
    'قبل ما تخرج، اعملي آبال.',
    'كي تبدا ديسبو كلمني.',
    'وين نلقى سي محسن؟',
  ];

  static const _model = ModelDescriptor(
    id: 'demo-aeb-tn',
    version: '0.1.0',
    runtime: 'scripted',
  );

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    final sequence = int.parse(turn.id.substring(turn.id.lastIndexOf('-') + 1));
    final text = _phrases[sequence % _phrases.length];
    return TranscriptHypothesis(
      rawText: text,
      displayText: text,
      locale: 'aeb-TN',
      model: _model,
      confidence: 1,
    );
  }

  @override
  Future<void> close() async {}
}
