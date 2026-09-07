import 'package:aurisia_mobile/features/transcription/application/streaming_hypothesis_policy.dart';
import 'package:aurisia_mobile/features/transcription/application/live_transcription_profile.dart';
import 'package:aurisia_mobile/features/transcription/domain/model_descriptor.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcript_candidate.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcript_hypothesis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StablePartialTracker', () {
    test('trusts only a repeated, meaningful partial', () {
      final tracker = const StreamingHypothesisPolicy().createTracker();

      tracker.observe(_hypothesis('نمشي للصيدلية', isFinal: false));
      expect(tracker.stable, isNull);

      tracker.observe(_hypothesis('نمشي للصيدلية', isFinal: false));
      expect(tracker.stable?.displayText, 'نمشي للصيدلية');
    });

    test('reset forgets hypotheses from the previous turn', () {
      final tracker = const StreamingHypothesisPolicy().createTracker();
      tracker
        ..observe(_hypothesis('صباح الخير', isFinal: false))
        ..observe(_hypothesis('صباح الخير', isFinal: false))
        ..reset();

      expect(tracker.latest, isNull);
      expect(tracker.stable, isNull);
    });
  });

  group('primary final selection', () {
    const policy = StreamingHypothesisPolicy();

    test('protects a stable partial from an unrelated weak final', () {
      final stable = _hypothesis(
        'نمشي للصيدلية و نرجع',
        confidence: 0.84,
        isFinal: false,
      );

      final selection = policy.selectPrimaryFinal(
        finalHypothesis: _hypothesis('نمشي للمدرسة غدوة', confidence: 0.61),
        stablePartial: stable,
        latestPartial: stable,
      );

      expect(selection.hypothesis?.displayText, stable.displayText);
      expect(selection.hypothesis?.isFinal, isTrue);
      expect(
        selection.reason,
        HypothesisSelectionReason.stablePartialProtected,
      );
    });

    test('accepts a final that extends the stable partial', () {
      final stable = _hypothesis('صباح الخير', isFinal: false);

      final selection = policy.selectPrimaryFinal(
        finalHypothesis: _hypothesis('صباح الخير يا صديقي'),
        stablePartial: stable,
        latestPartial: stable,
      );

      expect(selection.hypothesis?.displayText, 'صباح الخير يا صديقي');
      expect(selection.reason, HypothesisSelectionReason.finalExtension);
    });

    test('accepts a materially more confident final', () {
      final selection = policy.selectPrimaryFinal(
        finalHypothesis: _hypothesis('نمشي غدوة', confidence: 0.91),
        stablePartial: _hypothesis(
          'نمشي اليوم',
          confidence: 0.74,
          isFinal: false,
        ),
        latestPartial: null,
      );

      expect(selection.hypothesis?.displayText, 'نمشي غدوة');
      expect(selection.reason, HypothesisSelectionReason.finalConfidence);
    });

    test('uses the latest partial when the final is empty', () {
      final latest = _hypothesis('شنوة حوالك', isFinal: false);

      final selection = policy.selectPrimaryFinal(
        finalHypothesis: _hypothesis(''),
        stablePartial: null,
        latestPartial: latest,
      );

      expect(selection.hypothesis?.displayText, latest.displayText);
      expect(selection.hypothesis?.isFinal, isTrue);
    });
  });

  group('final refinement selection', () {
    const policy = StreamingHypothesisPolicy();

    test('protects a trusted baseline from a divergent refinement', () {
      final baseline = _hypothesis(
        'التعليم أساس تقدم المجتمعات',
        confidence: 0.87,
      );

      final selection = policy.selectRefinement(
        baseline: baseline,
        refinement: _hypothesis('اليوم نذهب إلى المكتبة', confidence: 0.7),
      );

      expect(selection.hypothesis, same(baseline));
      expect(selection.reason, HypothesisSelectionReason.baselineProtected);
    });

    test('accepts an agreeing refinement', () {
      final selection = policy.selectRefinement(
        baseline: _hypothesis('التعليم أساس تقدم المجتمعات', confidence: 0.87),
        refinement: _hypothesis('التعليم أساس تقدم المجتمع', confidence: 0.75),
      );

      expect(selection.hypothesis?.displayText, 'التعليم أساس تقدم المجتمع');
      expect(selection.reason, HypothesisSelectionReason.refinementAgreement);
    });

    test('protects leading and trailing words from an unscored refinement', () {
      const boundaryPolicy = StreamingHypothesisPolicy(
        minimumRefinementSimilarity: 0.5,
      );
      final baseline = _hypothesis(
        'تتغير درجات الحرارة خلال فصل الصيف',
        confidence: 0.8,
      );

      final selection = boundaryPolicy.selectRefinement(
        baseline: baseline,
        refinement: _hypothesis('درجات الحرارة خلال فصل'),
      );

      expect(selection.hypothesis, same(baseline));
      expect(
        selection.reason,
        HypothesisSelectionReason.refinementBoundaryProtected,
      );
    });

    test('rejects a long unscored completion of a short baseline', () {
      const guardedPolicy = StreamingHypothesisPolicy(
        minimumRefinementSimilarity: 0.78,
      );
      final baseline = _hypothesis('تختلف الظواهر الكونية');

      final selection = guardedPolicy.selectRefinement(
        baseline: baseline,
        refinement: _hypothesis(
          'تختلف الظواهر الكونية باختلاف درجات الحرارة '
          'والضغط وحركة الرياح عبر الفصول',
        ),
      );

      expect(selection.hypothesis, same(baseline));
      expect(selection.reason, HypothesisSelectionReason.baselineProtected);
    });

    test('allows minor spelling correction at transcript boundaries', () {
      final selection = policy.selectRefinement(
        baseline: _hypothesis('تتغير درجات الحراره مع الفصول'),
        refinement: _hypothesis('تتغير درجات الحرارة مع الفصول'),
      );

      expect(
        selection.hypothesis?.displayText,
        'تتغير درجات الحرارة مع الفصول',
      );
      expect(selection.reason, HypothesisSelectionReason.refinementAgreement);
    });

    test('protects even a weak baseline from an unscored rewrite', () {
      final selection = policy.selectRefinement(
        baseline: _hypothesis('كلام غير واضح', confidence: 0.42),
        refinement: _hypothesis('الطقس جميل هذا الصباح'),
      );

      expect(selection.hypothesis?.displayText, 'كلام غير واضح');
      expect(selection.reason, HypothesisSelectionReason.baselineProtected);
    });

    test('permits a divergent refinement with a confidence advantage', () {
      final selection = policy.selectRefinement(
        baseline: _hypothesis('كلام غير واضح', confidence: 0.42),
        refinement: _hypothesis('الطقس جميل هذا الصباح', confidence: 0.75),
      );

      expect(selection.hypothesis?.displayText, 'الطقس جميل هذا الصباح');
      expect(selection.reason, HypothesisSelectionReason.refinementConfidence);
    });

    test('can designate an unscored final engine as authoritative', () {
      const preferredPolicy = StreamingHypothesisPolicy(
        preferUnscoredRefinement: true,
      );
      final selection = preferredPolicy.selectRefinement(
        baseline: _hypothesis('كلام غير واضح تماما'),
        refinement: _hypothesis('تؤثر الحرارة في حركة الرياح'),
      );

      expect(selection.hypothesis?.displayText, 'تؤثر الحرارة في حركة الرياح');
      expect(selection.reason, HypothesisSelectionReason.preferredRefinement);
    });

    test('accepts refinement supported by a near-top baseline alternative', () {
      const consensusPolicy = StreamingHypothesisPolicy(
        minimumRefinementSimilarity: 0.99,
        minimumAlternativeConsensusSimilarity: 0.99,
      );
      final baseline = _hypothesis(
        'تؤثر درجات الحرارة في حركة الرياح السريعة',
        confidence: 0.48,
        alternatives: const <TranscriptCandidate>[
          TranscriptCandidate(
            text: 'تؤثر درجات الحرارة في حركة الرياح السريعة',
          ),
          TranscriptCandidate(
            text: 'تؤثر درجات الرطوبة في حركة الرياح السريعة',
          ),
        ],
      );

      final selection = consensusPolicy.selectRefinement(
        baseline: baseline,
        refinement: _hypothesis('تؤثر درجات الرطوبة في حركة الرياح السريعة'),
      );

      expect(
        selection.hypothesis?.displayText,
        'تؤثر درجات الرطوبة في حركة الرياح السريعة',
      );
      expect(
        selection.reason,
        HypothesisSelectionReason.refinementAlternativeConsensus,
      );
    });

    test('rejects consensus outside the configured alternative rank', () {
      const consensusPolicy = StreamingHypothesisPolicy(
        minimumRefinementSimilarity: 0.99,
        minimumAlternativeConsensusSimilarity: 0.99,
        maximumAlternativeConsensusRank: 2,
      );
      final baseline = _hypothesis(
        'تؤثر درجات الحرارة في حركة الرياح السريعة',
        confidence: 0.7,
        alternatives: const <TranscriptCandidate>[
          TranscriptCandidate(
            text: 'تؤثر درجات الحرارة في حركة الرياح السريعة',
          ),
          TranscriptCandidate(
            text: 'تؤثر درجات الرطوبة في حركة الرياح السريعة',
          ),
          TranscriptCandidate(text: 'تؤثر درجات الضغط في حركة الرياح السريعة'),
        ],
      );

      final selection = consensusPolicy.selectRefinement(
        baseline: baseline,
        refinement: _hypothesis('تؤثر درجات الضغط في حركة الرياح السريعة'),
      );

      expect(selection.hypothesis, same(baseline));
      expect(selection.reason, HypothesisSelectionReason.baselineProtected);
    });

    test('formal profile accepts the better captured Qwen correction', () {
      final policy = LiveTranscriptionProfile.formalArabic.hypothesisPolicy;

      final selection = policy.selectRefinement(
        baseline: _hypothesis('تغير درجات الحرر في صيف'),
        refinement: _hypothesis('تتغير درجات الحرارة في فصل الصيف.'),
      );

      expect(
        selection.hypothesis?.displayText,
        'تتغير درجات الحرارة في فصل الصيف.',
      );
      expect(selection.reason, HypothesisSelectionReason.preferredRefinement);
    });

    test('formal profile rejects a speculative completion of a short turn', () {
      final policy = LiveTranscriptionProfile.formalArabic.hypothesisPolicy;
      final baseline = _hypothesis('أما');

      final selection = policy.selectRefinement(
        baseline: baseline,
        refinement: _hypothesis('أما اليوم فسنتحدث عن الظواهر الكونية'),
      );

      expect(selection.hypothesis, same(baseline));
      expect(selection.reason, HypothesisSelectionReason.baselineProtected);
    });

    test('formal profile recovers a strongly cropped sentence', () {
      final policy = LiveTranscriptionProfile.formalArabic.hypothesisPolicy;

      final selection = policy.selectRefinement(
        baseline: _hypothesis('حرارة فصل صيف'),
        refinement: _hypothesis('تتغير درجات الحرارة في فصل الصيف.'),
      );

      expect(
        selection.hypothesis?.displayText,
        'تتغير درجات الحرارة في فصل الصيف.',
      );
      expect(selection.reason, HypothesisSelectionReason.preferredRefinement);
    });

    test('formal profile recovers a cropped expression', () {
      final policy = LiveTranscriptionProfile.formalArabic.hypothesisPolicy;

      final selection = policy.selectRefinement(
        baseline: _hypothesis('حركة الرياح'),
        refinement: _hypothesis('تؤثر درجات الحرارة في حركة الرياح.'),
      );

      expect(
        selection.hypothesis?.displayText,
        'تؤثر درجات الحرارة في حركة الرياح.',
      );
      expect(selection.reason, HypothesisSelectionReason.preferredRefinement);
    });

    test('formal profile rejects repetitive generative output', () {
      final policy = LiveTranscriptionProfile.formalArabic.hypothesisPolicy;
      final baseline = _hypothesis('في مثلا يعني');

      final selection = policy.selectRefinement(
        baseline: baseline,
        refinement: _hypothesis('ما أجعلهم مثال مثال مثال مثال للتلاميذ'),
      );

      expect(selection.hypothesis, same(baseline));
      expect(selection.reason, HypothesisSelectionReason.baselineProtected);
    });

    test('formal profile rejects a duplicate introduced by refinement', () {
      final policy = LiveTranscriptionProfile.formalArabic.hypothesisPolicy;
      final baseline = _hypothesis(
        'نظارات نظرات تأملية في بعض الظواهر الكونية',
      );

      final selection = policy.selectRefinement(
        baseline: baseline,
        refinement: _hypothesis(
          'في نظارات نظارات تأملية في بعض الظواهر الكونية',
        ),
      );

      expect(selection.hypothesis, same(baseline));
      expect(selection.reason, HypothesisSelectionReason.baselineProtected);
    });

    test('formal profile preserves a repetition heard by both engines', () {
      final policy = LiveTranscriptionProfile.formalArabic.hypothesisPolicy;

      final selection = policy.selectRefinement(
        baseline: _hypothesis('أخص أخص بالذكر ظاهرة اختلاف الفصول'),
        refinement: _hypothesis('أخص أخص بالذكر ظاهرة اختلاف الفصول.'),
      );

      expect(
        selection.hypothesis?.displayText,
        'أخص أخص بالذكر ظاهرة اختلاف الفصول.',
      );
      expect(selection.reason, HypothesisSelectionReason.refinementAgreement);
    });

    test('Tunisian profile recovers Panadol from the final recognizer', () {
      final policy =
          LiveTranscriptionProfile.tunisianConversation.hypothesisPolicy;

      final selection = policy.selectRefinement(
        baseline: _hypothesis('جيب باكو قراندور'),
        refinement: _hypothesis('جيب بكو بانادول.'),
      );

      expect(selection.hypothesis?.displayText, 'جيب بكو بانادول.');
      expect(selection.reason, HypothesisSelectionReason.preferredRefinement);
    });

    test('Tunisian profile keeps a more complete leading phrase', () {
      final policy =
          LiveTranscriptionProfile.tunisianConversation.hypothesisPolicy;
      final baseline = _hypothesis('وقتاش باش تمشي للفارماسي');

      final selection = policy.selectRefinement(
        baseline: baseline,
        refinement: _hypothesis('وقتيش بشتمشي الفرمسي.'),
      );

      expect(selection.hypothesis, same(baseline));
      expect(
        selection.reason,
        HypothesisSelectionReason.refinementBoundaryProtected,
      );
    });
  });
}

const _model = ModelDescriptor(id: 'test-asr', version: '1', runtime: 'fake');

TranscriptHypothesis _hypothesis(
  String text, {
  double? confidence,
  bool isFinal = true,
  List<TranscriptCandidate> alternatives = const <TranscriptCandidate>[],
}) {
  return TranscriptHypothesis(
    rawText: text,
    displayText: text,
    locale: 'ar-TN',
    model: _model,
    confidence: confidence,
    isFinal: isFinal,
    alternatives: alternatives,
  );
}
