import 'package:aurisia_mobile/features/transcription/application/live_transcription_profile.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcription_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('profiles keep long sermon context and responsive speaker changes', () {
    final conversation = LiveTranscriptionProfile.forId(
      TranscriptionProfile.tunisianConversation,
    );
    final sermon = LiveTranscriptionProfile.forId(
      TranscriptionProfile.formalArabicSermon,
    );

    expect(
      sermon.maximumSpeechSeconds,
      greaterThan(conversation.maximumSpeechSeconds),
    );
    expect(conversation.newSpeakerConfirmationCount, 3);
    expect(sermon.newSpeakerConfirmationCount, 3);
    expect(
      sermon.minimumSpeakerEmbeddingDuration,
      greaterThan(conversation.minimumSpeakerEmbeddingDuration),
    );
    expect(conversation.speakerSwitchMargin, 0.08);
    expect(sermon.speakerSwitchMargin, 0.1);
    expect(conversation.maximumSpeakers, 4);
    expect(sermon.maximumSpeakers, 4);
    expect(conversation.minimumSilenceSeconds, 0.5);
    expect(sermon.minimumSilenceSeconds, 0.55);
    expect(sermon.maximumSpeechSeconds, 14);
    expect(
      conversation.leadingSpeechPadding,
      const Duration(milliseconds: 250),
    );
    expect(
      conversation.trailingSpeechPadding,
      const Duration(milliseconds: 250),
    );
    expect(sermon.leadingSpeechPadding, const Duration(milliseconds: 750));
    expect(sermon.trailingSpeechPadding, const Duration(milliseconds: 450));
    expect(
      conversation.displayLexiconAssetPath,
      'assets/language_packs/aeb-TN/display_lexicon.json',
    );
    expect(
      sermon.displayLexiconAssetPath,
      'assets/language_packs/ar-formal/display_lexicon.json',
    );
    expect(conversation.normalizeSustainedPhonation, isFalse);
    expect(sermon.normalizeSustainedPhonation, isTrue);
    expect(conversation.maximumRefinementAge, const Duration(seconds: 4));
    expect(sermon.maximumRefinementAge, const Duration(seconds: 8));
    expect(
      conversation.hypothesisPolicy.minimumFinalSimilarity,
      greaterThan(sermon.hypothesisPolicy.minimumFinalSimilarity),
    );
    expect(sermon.hypothesisPolicy.minimumRefinementSimilarity, 0.78);
    expect(sermon.hypothesisPolicy.minimumAlternativeConsensusSimilarity, 0.88);
    expect(sermon.hypothesisPolicy.maximumAlternativeConsensusRank, 2);
    expect(sermon.hypothesisPolicy.refinementConfidenceAdvantage, 0.12);
    expect(sermon.hypothesisPolicy.preferUnscoredRefinement, isTrue);
    expect(sermon.hypothesisPolicy.minimumPreferredBaselineTokens, 2);
    expect(sermon.hypothesisPolicy.minimumPreferredRefinementSimilarity, 0.2);
    expect(sermon.hypothesisPolicy.minimumPreferredRefinementTokenRatio, 0.65);
    expect(sermon.hypothesisPolicy.maximumPreferredRefinementLengthRatio, 4.2);
    expect(sermon.hypothesisPolicy.maximumPreferredRepeatedTokenRun, 1);
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
    expect(sermon.finalAsrLanguageHint, 'Arabic');
  });
}
