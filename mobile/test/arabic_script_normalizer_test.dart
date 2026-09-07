import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/application/normalizing_transcription_engine.dart';
import 'package:aurisia_mobile/features/transcription/domain/model_descriptor.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/transcription_engine.dart';
import 'package:aurisia_mobile/features/transcription/domain/speech_turn.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcript_candidate.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcript_hypothesis.dart';
import 'package:aurisia_mobile/features/transcription/infrastructure/language/arabic_script_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('renders known Tunisian code-switches in Arabic script', () async {
    final normalizer = await ArabicScriptNormalizer.load();

    expect(
      normalizer.normalize(
        'امشي لل pharmacie جيب paquet panadol واعمل marche arrière ونظف el lavabo',
      ),
      'امشي لل فارماسي جيب باكو بانادول واعمل مارش أريار ونظف el لافابو',
    );
  });

  test('preserves unknown Latin terms and raw ASR output', () async {
    final normalizer = await ArabicScriptNormalizer.load();
    final engine = NormalizingTranscriptionEngine(
      engine: _RawEngine(),
      normalizer: normalizer,
    );
    final now = DateTime.utc(2026);

    final result = await engine.transcribe(
      SpeechTurn(
        id: 'turn-1',
        streamId: 'stream-1',
        startedAt: now,
        endedAt: now,
        sampleRateHz: 16000,
        channels: 1,
        samples: Float32List(1),
      ),
    );

    expect(result.rawText, 'نعمل appel مع Aurisia');
    expect(result.displayText, 'نعمل آبال مع Aurisia');
    expect(result.alternatives.single.text, 'نعمل آبال');
  });

  test(
    'normalizes observed medicine code-switch variants conservatively',
    () async {
      final normalizer = await ArabicScriptNormalizer.load();

      expect(
        normalizer.normalize(
          'تتعدى للفارمسي جيب باكو قراندور ولا paquet doliprane',
        ),
        'تتعدى للفارماسي جيب باكو بانادول ولا باكو دوليبران',
      );
    },
  );

  test('normalizes recurrent formal Arabic decoder confusions', () async {
    final normalizer = await ArabicScriptNormalizer.load(
      assetPath: 'assets/language_packs/ar-formal/display_lexicon.json',
    );

    expect(
      normalizer.normalize(
        'جعل ف اختلاف الظواهر الكونية عبارة للمستمعين '
        'ومجال لتذبر المستبد الصيرين',
      ),
      'جعل في اختلاف الظواهر الكونية عبرة للمستمعين '
      'ومجالاً لتدبر المستبصرين',
    );
    expect(
      normalizer.normalize(
        'بسمح لي أن أرافقكم اليومة في نظارات نظارات التأملية '
        'أكثر الناس تبصرة وتأملة وتذبورة',
      ),
      'اسمحوا لي أن أرافقكم اليوم في نظرات نظرات تأملية '
      'أكثر الناس تبصرا وتأملا وتدبرا',
    );
    expect(
      normalizer.normalize(
        'مقاومة استمرار الحياة لو اعتدت أكثر من مقدارها عن الأرض '
        'في أنو واحد شدة حرن',
      ),
      'مقومات استمرار الحياة لو ابتعدت أكثر من مقدارها عن الأرض '
      'في آن واحد شدة حر',
    );
    expect(
      normalizer.normalize('إلیها في مدارها بما علیها'),
      'إليها في مدارها بما عليها',
    );
    expect(
      normalizer.normalize(
        'تتغير درجات الحرارة إUٌٍأ واليوم تختلف الظواهر الكونية '
        'في نظارات نظارات تأملية',
      ),
      isEmpty,
    );
  });
}

class _RawEngine implements TranscriptionEngine {
  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    return const TranscriptHypothesis(
      rawText: 'نعمل appel مع Aurisia',
      displayText: 'نعمل appel مع Aurisia',
      locale: 'aeb-TN',
      model: ModelDescriptor(id: 'fake', version: '1', runtime: 'fake'),
      alternatives: <TranscriptCandidate>[
        TranscriptCandidate(text: 'نعمل appel', confidence: 0.4),
      ],
    );
  }

  @override
  Future<void> close() async {}
}
