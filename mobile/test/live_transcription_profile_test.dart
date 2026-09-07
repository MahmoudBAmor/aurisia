import 'package:aurisia_mobile/features/transcription/application/live_transcription_profile.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcription_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profiles keep long formal context and responsive speaker changes', () {
    final conversation = LiveTranscriptionProfile.forId(
      TranscriptionProfile.tunisianConversation,
    );
    final formal = LiveTranscriptionProfile.forId(
      TranscriptionProfile.formalArabic,
    );

    expect(
      formal.maximumSpeechSeconds,
      greaterThan(conversation.maximumSpeechSeconds),
    );
    expect(conversation.newSpeakerConfirmationCount, 3);
    expect(formal.newSpeakerConfirmationCount, 3);
    expect(
      formal.minimumSpeakerEmbeddingDuration,
      greaterThan(conversation.minimumSpeakerEmbeddingDuration),
    );
    expect(conversation.speakerSwitchMargin, 0.08);
    expect(formal.speakerSwitchMargin, 0.1);
    expect(conversation.maximumSpeakers, 4);
    expect(formal.maximumSpeakers, 4);
    expect(conversation.minimumSilenceSeconds, 0.5);
    expect(formal.minimumSilenceSeconds, 0.55);
    expect(formal.maximumSpeechSeconds, 14);
    expect(
      conversation.leadingSpeechPadding,
      const Duration(milliseconds: 250),
    );
    expect(
      conversation.trailingSpeechPadding,
      const Duration(milliseconds: 250),
    );
    expect(formal.leadingSpeechPadding, const Duration(milliseconds: 750));
    expect(formal.trailingSpeechPadding, const Duration(milliseconds: 450));
    expect(
      conversation.displayLexiconAssetPath,
      'assets/language_packs/aeb-TN/display_lexicon.json',
    );
    expect(
      formal.displayLexiconAssetPath,
      'assets/language_packs/ar-formal/display_lexicon.json',
    );
    expect(conversation.normalizeSustainedPhonation, isFalse);
    expect(formal.normalizeSustainedPhonation, isTrue);
    expect(conversation.maximumRefinementAge, const Duration(seconds: 4));
    expect(formal.maximumRefinementAge, const Duration(seconds: 8));
    expect(
      conversation.hypothesisPolicy.minimumFinalSimilarity,
      greaterThan(formal.hypothesisPolicy.minimumFinalSimilarity),
    );
    expect(formal.hypothesisPolicy.minimumRefinementSimilarity, 0.78);
    expect(formal.hypothesisPolicy.minimumAlternativeConsensusSimilarity, 0.88);
    expect(formal.hypothesisPolicy.maximumAlternativeConsensusRank, 2);
    expect(formal.hypothesisPolicy.refinementConfidenceAdvantage, 0.12);
    expect(formal.hypothesisPolicy.preferUnscoredRefinement, isTrue);
    expect(formal.hypothesisPolicy.minimumPreferredBaselineTokens, 2);
    expect(formal.hypothesisPolicy.minimumPreferredRefinementSimilarity, 0.2);
    expect(formal.hypothesisPolicy.minimumPreferredRefinementTokenRatio, 0.65);
    expect(formal.hypothesisPolicy.maximumPreferredRefinementLengthRatio, 4.2);
    expect(formal.hypothesisPolicy.maximumPreferredRepeatedTokenRun, 1);
    expect(conversation.hypothesisPolicy.preferUnscoredRefinement, isTrue);
    expect(
      conversation.hypothesisPolicy.minimumPreferredRefinementSimilarity,
      0.66,
    );
    expect(
      conversation.hypothesisPolicy.minimumPreferredRefinementTokenRatio,
      1,
    );
    expect(
      conversation.hypothesisPolicy.minimumPreferredRefinementLeadingSimilarity,
      0.67,
    );
    expect(conversation.finalAsrLanguageHint, 'Arabic');
    expect(formal.finalAsrLanguageHint, 'Arabic');
  });
}
