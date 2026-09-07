import '../domain/transcription_profile.dart';
import 'streaming_hypothesis_policy.dart';

class LiveTranscriptionProfile {
  const LiveTranscriptionProfile({
    required this.id,
    required this.minimumSilenceSeconds,
    required this.maximumSpeechSeconds,
    required this.maximumRefinementAge,
    required this.leadingSpeechPadding,
    required this.trailingSpeechPadding,
    required this.displayLexiconAssetPath,
    required this.speakerSimilarityThreshold,
    required this.pendingSpeakerSimilarityThreshold,
    required this.speakerSwitchMargin,
    required this.newSpeakerConfirmationCount,
    required this.minimumSpeakerEmbeddingDuration,
    required this.maximumSpeakers,
    required this.hypothesisPolicy,
    required this.finalAsrLanguageHint,
    this.normalizeSustainedPhonation = false,
    this.finalAsrTrailingSilence = Duration.zero,
  });

  factory LiveTranscriptionProfile.forId(TranscriptionProfile id) {
    return switch (id) {
      TranscriptionProfile.tunisianConversation => tunisianConversation,
      TranscriptionProfile.formalArabic => formalArabic,
    };
  }

  static const tunisianConversation = LiveTranscriptionProfile(
    id: TranscriptionProfile.tunisianConversation,
    minimumSilenceSeconds: 0.5,
    maximumSpeechSeconds: 12,
    maximumRefinementAge: Duration(seconds: 4),
    leadingSpeechPadding: Duration(milliseconds: 250),
    trailingSpeechPadding: Duration(milliseconds: 250),
    displayLexiconAssetPath:
        'assets/language_packs/aeb-TN/display_lexicon.json',
    speakerSimilarityThreshold: 0.52,
    pendingSpeakerSimilarityThreshold: 0.74,
    speakerSwitchMargin: 0.08,
    newSpeakerConfirmationCount: 3,
    minimumSpeakerEmbeddingDuration: Duration(milliseconds: 1000),
    maximumSpeakers: 4,
    finalAsrLanguageHint: 'Arabic',
    hypothesisPolicy: StreamingHypothesisPolicy(
      minimumFinalSimilarity: 0.64,
      trustedFinalConfidence: 0.92,
      preferUnscoredRefinement: true,
      minimumPreferredRefinementSimilarity: 0.66,
      minimumPreferredRefinementTokenRatio: 1,
      minimumPreferredRefinementLeadingSimilarity: 0.67,
      maximumPreferredRefinementLengthRatio: 1.35,
    ),
  );

  static const formalArabic = LiveTranscriptionProfile(
    id: TranscriptionProfile.formalArabic,
    minimumSilenceSeconds: 0.55,
    maximumSpeechSeconds: 14,
    maximumRefinementAge: Duration(seconds: 8),
    leadingSpeechPadding: Duration(milliseconds: 750),
    trailingSpeechPadding: Duration(milliseconds: 450),
    displayLexiconAssetPath:
        'assets/language_packs/ar-formal/display_lexicon.json',
    speakerSimilarityThreshold: 0.54,
    pendingSpeakerSimilarityThreshold: 0.76,
    speakerSwitchMargin: 0.1,
    newSpeakerConfirmationCount: 3,
    minimumSpeakerEmbeddingDuration: Duration(milliseconds: 1200),
    maximumSpeakers: 4,
    finalAsrLanguageHint: 'Arabic',
    normalizeSustainedPhonation: true,
    hypothesisPolicy: StreamingHypothesisPolicy(
      minimumFinalSimilarity: 0.6,
      trustedFinalConfidence: 0.9,
      minimumRefinementSimilarity: 0.78,
      minimumAlternativeConsensusSimilarity: 0.88,
      maximumAlternativeConsensusRank: 2,
      refinementConfidenceAdvantage: 0.12,
      trustedRefinementConfidence: 0.94,
      preferUnscoredRefinement: true,
      minimumPreferredBaselineTokens: 2,
      minimumPreferredRefinementSimilarity: 0.2,
      minimumPreferredRefinementTokenRatio: 0.65,
      maximumPreferredRefinementLengthRatio: 4.2,
      maximumPreferredRepeatedTokenRun: 1,
    ),
  );

  final TranscriptionProfile id;
  final double minimumSilenceSeconds;
  final double maximumSpeechSeconds;
  final Duration maximumRefinementAge;
  final Duration leadingSpeechPadding;
  final Duration trailingSpeechPadding;
  final String displayLexiconAssetPath;
  final double speakerSimilarityThreshold;
  final double pendingSpeakerSimilarityThreshold;
  final double speakerSwitchMargin;
  final int newSpeakerConfirmationCount;
  final Duration minimumSpeakerEmbeddingDuration;
  final int maximumSpeakers;
  final StreamingHypothesisPolicy hypothesisPolicy;
  final String finalAsrLanguageHint;
  final bool normalizeSustainedPhonation;
  final Duration finalAsrTrailingSilence;
}
