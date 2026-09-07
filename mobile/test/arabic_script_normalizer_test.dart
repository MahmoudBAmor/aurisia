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
        'جعل ف اختلاف الظواهر الكونية عبارة للمؤمنين '
        'ومجال لتذبر المستبد الصيرين',
      ),
      'جعل في اختلاف الظواهر الكونية عبرة للمؤمنين '
      'ومجالاً لتدبر المستبصرين',
    );
    expect(
      normalizer.normalize(
        'وأشهد أن اللهم إله الله وحده لا شريكة له '
        'إن في ذلك العبرة لقول الأبصار',
      ),
      'وأشهد أن لا إله إلا الله وحده لا شريك له '
      'إن في ذلك لعبرة لأولي الأبصار',
    );
    expect(
      normalizer.normalize(
        'ومجالا لتذبّر المستبصرين إن في ذلك لعبرة لوللإبصار '
        'وأشهد أن سيدنا وحبي بننا وعما منا واسوتنا محمدًا '
        'أكثر الناس تبصراً وتاملاً وتذبورة',
      ),
      'ومجالاً لتدبر المستبصرين إن في ذلك لعبرة لأولي الأبصار '
      'وأشهد أن سيدنا وحبيبنا وإمامنا وأسوتنا محمدًا '
      'أكثر الناس تبصراً وتأملا وتدبرا',
    );
    expect(
      normalizer.normalize(
        'فالله مصلي وسلم وبارك عليه وعلى آله وصحبه وتبعين '
        'بسمحولي أن أرافقكم في نظارات نظارات تأملية '
        'أخص أخص بالذكرى كائة من آيات الله الح الحياة '
        'فما الذي ينففما الذي ينجي الإنسان',
      ),
      'فاللهم صل وسلم وبارك عليه وعلى آله وصحبه والتابعين '
      'اسمحوا لي أن أرافقكم في نظرات نظرات تأملية '
      'أخص بالذكر كآية من آيات الله الحياة فما الذي ينجي الإنسان',
    );
    expect(
      normalizer.normalize(
        'وأشهد أن لاها إلا الله وحده لا شريك له '
        'يقلب بالشر والخير الليلة والنهر إن في ذلك لعبرة لقول الإبصار '
        'وعما منا وأسواتنا أكثر الناس تبصرة وتأملة وتدبرة '
        'وصحبه وتابعين',
      ),
      'وأشهد أن لا إله إلا الله وحده لا شريك له '
      'يقلب بالشر والخير الليل والنهار إن في ذلك لعبرة لأولي الأبصار '
      'وإمامنا وأسوتنا أكثر الناس تبصرا وتأملا وتدبرا '
      'وصحبه والتابعين',
    );
    expect(
      normalizer.normalize(
        'أما بعد فياعه المؤمنون الكرم بسمح لي أن أرافقكم اليومة '
        'من خلال خصوبتنا هذه في نظارات نظارات التأملية '
        'وهي من بديع الصنع الله ومن مقاومة استمرار الحياة '
        'لو اعتدت أكثر من مقدارها عن الأرض في أنو واحد شدة حرن',
      ),
      'أما بعد فيا أيها المؤمنون الكرام اسمحوا لي أن أرافقكم اليوم '
      'من خلال خطبتنا هذه في نظرات نظرات تأملية '
      'وهي من بديع صنع الله ومن مقومات استمرار الحياة '
      'لو ابتعدت أكثر من مقدارها عن الأرض في آن واحد شدة حر',
    );
    expect(
      normalizer.normalize('إلیها في مدارها بما علیها'),
      'إليها في مدارها بما عليها',
    );
    expect(
      normalizer.normalize(
        'أن سيدنا وحبيبنا إUٌٍأ واليوم يقلب بالشر والخير الليل والنهر '
        'إن في ذلك لعبرة اللولل الإبصار وحبي بنى وعما منى وعسوتنا '
        'فالله مصلي وسلّم',
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
