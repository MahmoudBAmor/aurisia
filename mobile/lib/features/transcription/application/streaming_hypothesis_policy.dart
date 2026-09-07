import '../domain/transcript_hypothesis.dart';

enum HypothesisSelectionReason {
  empty,
  noStablePartial,
  exactMatch,
  finalExtension,
  finalConfidence,
  finalAgreement,
  stablePartialProtected,
  refinementWithoutBaseline,
  refinementAgreement,
  refinementAlternativeConsensus,
  refinementConfidence,
  preferredRefinement,
  refinementBoundaryProtected,
  baselineProtected,
}

class HypothesisSelection {
  const HypothesisSelection({
    required this.hypothesis,
    required this.reason,
    this.similarity,
  });

  final TranscriptHypothesis? hypothesis;
  final HypothesisSelectionReason reason;
  final double? similarity;
}

/// Keeps a partial only after the recognizer has emitted it unchanged across
/// multiple audio frames. This avoids treating a fleeting decoder state as a
/// reliable transcript.
class StablePartialTracker {
  StablePartialTracker({
    required this.minimumObservations,
    required this.minimumCharacters,
  }) {
    if (minimumObservations < 2) {
      throw ArgumentError.value(
        minimumObservations,
        'minimumObservations',
        'must be at least 2',
      );
    }
    if (minimumCharacters <= 0) {
      throw ArgumentError.value(minimumCharacters, 'minimumCharacters');
    }
  }

  final int minimumObservations;
  final int minimumCharacters;
  TranscriptHypothesis? _latest;
  TranscriptHypothesis? _current;
  TranscriptHypothesis? _stable;
  int _currentObservations = 0;

  TranscriptHypothesis? get latest => _latest;
  TranscriptHypothesis? get stable => _stable;

  void observe(TranscriptHypothesis hypothesis) {
    if (hypothesis.displayText.trim().isEmpty) {
      return;
    }
    _latest = hypothesis;
    if (_comparisonText(_current?.displayText ?? '') ==
        _comparisonText(hypothesis.displayText)) {
      _currentObservations += 1;
    } else {
      _current = hypothesis;
      _currentObservations = 1;
    }
    if (_currentObservations >= minimumObservations &&
        _comparisonText(hypothesis.displayText).length >= minimumCharacters) {
      _stable = hypothesis;
    }
  }

  void reset() {
    _latest = null;
    _current = null;
    _stable = null;
    _currentObservations = 0;
  }
}

/// Model-neutral arbitration for visible streaming and refinement results.
///
/// A decoder final is normally preferred. A stable partial is retained only
/// when the final is a substantial, insufficiently confident rewrite. An
/// optional second ASR engine follows a similar agreement gate so a trusted
/// first result is not replaced blindly.
class StreamingHypothesisPolicy {
  const StreamingHypothesisPolicy({
    this.minimumStablePartialObservations = 2,
    this.minimumStablePartialCharacters = 5,
    this.minimumFinalSimilarity = 0.62,
    this.finalConfidenceAdvantage = 0.08,
    this.trustedFinalConfidence = 0.92,
    this.minimumRefinementSimilarity = 0.72,
    this.minimumRefinementBoundarySimilarity = 0.68,
    this.refinementBoundaryTokenCount = 2,
    this.minimumAlternativeConsensusSimilarity = 0.86,
    this.maximumAlternativeConsensusRank = 2,
    this.refinementConfidenceAdvantage = 0.1,
    this.trustedRefinementConfidence = 0.92,
    this.preferUnscoredRefinement = false,
    this.minimumPreferredBaselineTokens = 1,
    this.minimumPreferredRefinementSimilarity = 0,
    this.minimumPreferredRefinementTokenRatio = 0,
    this.minimumPreferredRefinementLeadingSimilarity = 0,
    this.maximumPreferredRefinementLengthRatio = 10,
    this.maximumPreferredRepeatedTokenRun = 2,
  }) : assert(minimumStablePartialObservations >= 2),
       assert(minimumStablePartialCharacters > 0),
       assert(minimumFinalSimilarity >= 0 && minimumFinalSimilarity <= 1),
       assert(finalConfidenceAdvantage >= 0 && finalConfidenceAdvantage <= 1),
       assert(trustedFinalConfidence >= 0 && trustedFinalConfidence <= 1),
       assert(
         minimumRefinementSimilarity >= 0 && minimumRefinementSimilarity <= 1,
       ),
       assert(
         minimumRefinementBoundarySimilarity >= 0 &&
             minimumRefinementBoundarySimilarity <= 1,
       ),
       assert(refinementBoundaryTokenCount > 0),
       assert(
         minimumAlternativeConsensusSimilarity >= 0 &&
             minimumAlternativeConsensusSimilarity <= 1,
       ),
       assert(maximumAlternativeConsensusRank >= 2),
       assert(
         refinementConfidenceAdvantage >= 0 &&
             refinementConfidenceAdvantage <= 1,
       ),
       assert(
         trustedRefinementConfidence >= 0 && trustedRefinementConfidence <= 1,
       ),
       assert(
         minimumPreferredRefinementSimilarity >= 0 &&
             minimumPreferredRefinementSimilarity <= 1,
       ),
       assert(
         minimumPreferredRefinementTokenRatio >= 0 &&
             minimumPreferredRefinementTokenRatio <= 1,
       ),
       assert(
         minimumPreferredRefinementLeadingSimilarity >= 0 &&
             minimumPreferredRefinementLeadingSimilarity <= 1,
       ),
       assert(maximumPreferredRefinementLengthRatio >= 1),
       assert(minimumPreferredBaselineTokens >= 1),
       assert(maximumPreferredRepeatedTokenRun >= 1);

  final int minimumStablePartialObservations;
  final int minimumStablePartialCharacters;
  final double minimumFinalSimilarity;
  final double finalConfidenceAdvantage;
  final double trustedFinalConfidence;
  final double minimumRefinementSimilarity;
  final double minimumRefinementBoundarySimilarity;
  final int refinementBoundaryTokenCount;
  final double minimumAlternativeConsensusSimilarity;
  final int maximumAlternativeConsensusRank;
  final double refinementConfidenceAdvantage;
  final double trustedRefinementConfidence;
  final bool preferUnscoredRefinement;
  final int minimumPreferredBaselineTokens;
  final double minimumPreferredRefinementSimilarity;
  final double minimumPreferredRefinementTokenRatio;
  final double minimumPreferredRefinementLeadingSimilarity;
  final double maximumPreferredRefinementLengthRatio;
  final int maximumPreferredRepeatedTokenRun;

  StablePartialTracker createTracker() => StablePartialTracker(
    minimumObservations: minimumStablePartialObservations,
    minimumCharacters: minimumStablePartialCharacters,
  );

  HypothesisSelection selectPrimaryFinal({
    required TranscriptHypothesis finalHypothesis,
    required TranscriptHypothesis? stablePartial,
    required TranscriptHypothesis? latestPartial,
  }) {
    final finalText = _comparisonText(finalHypothesis.displayText);
    final partial = stablePartial;
    if (finalText.isEmpty) {
      final fallback = partial ?? latestPartial;
      return HypothesisSelection(
        hypothesis: fallback == null ? null : _asFinal(fallback),
        reason: fallback == null
            ? HypothesisSelectionReason.empty
            : HypothesisSelectionReason.stablePartialProtected,
      );
    }
    if (partial == null) {
      return HypothesisSelection(
        hypothesis: finalHypothesis,
        reason: HypothesisSelectionReason.noStablePartial,
      );
    }

    final partialText = _comparisonText(partial.displayText);
    final similarity = _characterSimilarity(partialText, finalText);
    if (partialText == finalText) {
      return HypothesisSelection(
        hypothesis: finalHypothesis,
        reason: HypothesisSelectionReason.exactMatch,
        similarity: 1,
      );
    }
    if (finalText.startsWith(partialText)) {
      return HypothesisSelection(
        hypothesis: finalHypothesis,
        reason: HypothesisSelectionReason.finalExtension,
        similarity: similarity,
      );
    }

    final finalConfidence = finalHypothesis.confidence;
    final partialConfidence = partial.confidence;
    if ((finalConfidence != null &&
            finalConfidence >= trustedFinalConfidence) ||
        (finalConfidence != null &&
            partialConfidence != null &&
            finalConfidence - partialConfidence >= finalConfidenceAdvantage)) {
      return HypothesisSelection(
        hypothesis: finalHypothesis,
        reason: HypothesisSelectionReason.finalConfidence,
        similarity: similarity,
      );
    }
    if (similarity >= minimumFinalSimilarity) {
      return HypothesisSelection(
        hypothesis: finalHypothesis,
        reason: HypothesisSelectionReason.finalAgreement,
        similarity: similarity,
      );
    }
    return HypothesisSelection(
      hypothesis: _asFinal(partial),
      reason: HypothesisSelectionReason.stablePartialProtected,
      similarity: similarity,
    );
  }

  HypothesisSelection selectRefinement({
    required TranscriptHypothesis? baseline,
    required TranscriptHypothesis refinement,
  }) {
    final refinementText = _comparisonText(refinement.displayText);
    if (refinementText.isEmpty) {
      return HypothesisSelection(
        hypothesis: baseline,
        reason: baseline == null
            ? HypothesisSelectionReason.empty
            : HypothesisSelectionReason.baselineProtected,
      );
    }
    if (baseline == null || baseline.displayText.trim().isEmpty) {
      return HypothesisSelection(
        hypothesis: refinement,
        reason: HypothesisSelectionReason.refinementWithoutBaseline,
      );
    }

    final baselineText = _comparisonText(baseline.displayText);
    final similarity = _characterSimilarity(baselineText, refinementText);
    final baselineTokens = baselineText.split(' ');
    final refinementTokens = refinementText.split(' ');
    if (_hasRepeatedTokenRun(
          refinementTokens,
          maximumPreferredRepeatedTokenRun,
        ) &&
        !_hasRepeatedTokenRun(
          baselineTokens,
          maximumPreferredRepeatedTokenRun,
        )) {
      return HypothesisSelection(
        hypothesis: baseline,
        reason: HypothesisSelectionReason.baselineProtected,
        similarity: similarity,
      );
    }
    if ((refinementText.startsWith('$baselineText ') ||
            refinementText.endsWith(' $baselineText')) &&
        similarity >= minimumRefinementSimilarity) {
      return HypothesisSelection(
        hypothesis: refinement,
        reason: HypothesisSelectionReason.refinementAgreement,
        similarity: similarity,
      );
    }
    final preservesBoundaries = _preservesRefinementBoundaries(
      baselineText,
      refinementText,
    );
    final rejectedAtBoundary =
        !preservesBoundaries && similarity >= minimumRefinementSimilarity;
    if (preservesBoundaries &&
        (baselineText == refinementText ||
            similarity >= minimumRefinementSimilarity)) {
      return HypothesisSelection(
        hypothesis: refinement,
        reason: HypothesisSelectionReason.refinementAgreement,
        similarity: similarity,
      );
    }
    if (preservesBoundaries) {
      final alternativeConsensus = _alternativeConsensus(
        baseline,
        refinementText,
      );
      if (alternativeConsensus != null) {
        return HypothesisSelection(
          hypothesis: refinement,
          reason: HypothesisSelectionReason.refinementAlternativeConsensus,
          similarity: alternativeConsensus,
        );
      }
    }
    final baselineConfidence = baseline.confidence;
    final refinementConfidence = refinement.confidence;
    if (refinementConfidence != null &&
        (refinementConfidence >= trustedRefinementConfidence ||
            (baselineConfidence != null &&
                refinementConfidence - baselineConfidence >=
                    refinementConfidenceAdvantage))) {
      return HypothesisSelection(
        hypothesis: refinement,
        reason: HypothesisSelectionReason.refinementConfidence,
        similarity: similarity,
      );
    }
    if (preferUnscoredRefinement &&
        refinementConfidence == null &&
        _isPlausiblePreferredRefinement(
          baseline: baselineText,
          refinement: refinementText,
          similarity: similarity,
        )) {
      return HypothesisSelection(
        hypothesis: refinement,
        reason: HypothesisSelectionReason.preferredRefinement,
        similarity: similarity,
      );
    }
    return HypothesisSelection(
      hypothesis: baseline,
      reason: rejectedAtBoundary
          ? HypothesisSelectionReason.refinementBoundaryProtected
          : HypothesisSelectionReason.baselineProtected,
      similarity: similarity,
    );
  }

  bool _isPlausiblePreferredRefinement({
    required String baseline,
    required String refinement,
    required double similarity,
  }) {
    if (similarity < minimumPreferredRefinementSimilarity) {
      return false;
    }
    final baselineTokens = baseline.split(' ');
    final refinementTokens = refinement.split(' ');
    if (baselineTokens.length < minimumPreferredBaselineTokens ||
        _hasRepeatedTokenRun(
          refinementTokens,
          maximumPreferredRepeatedTokenRun,
        )) {
      return false;
    }
    final tokenRatio = refinementTokens.length / baselineTokens.length;
    if (tokenRatio < minimumPreferredRefinementTokenRatio) {
      return false;
    }
    final lengthRatio = refinement.length / baseline.length;
    if (lengthRatio > maximumPreferredRefinementLengthRatio) {
      return false;
    }
    final leadingSimilarity = _characterSimilarity(
      baselineTokens.first,
      refinementTokens.first,
    );
    return leadingSimilarity >= minimumPreferredRefinementLeadingSimilarity;
  }

  bool _preservesRefinementBoundaries(String baseline, String refinement) {
    final baselineTokens = baseline.split(' ');
    final refinementTokens = refinement.split(' ');
    final tokenCount = _minimumOfTwo(
      refinementBoundaryTokenCount,
      _minimumOfTwo(baselineTokens.length, refinementTokens.length),
    );
    final baselineStart = baselineTokens.take(tokenCount).join(' ');
    final refinementStart = refinementTokens.take(tokenCount).join(' ');
    final baselineEnd = baselineTokens
        .skip(baselineTokens.length - tokenCount)
        .join(' ');
    final refinementEnd = refinementTokens
        .skip(refinementTokens.length - tokenCount)
        .join(' ');
    return _characterSimilarity(baselineStart, refinementStart) >=
            minimumRefinementBoundarySimilarity &&
        _characterSimilarity(baselineEnd, refinementEnd) >=
            minimumRefinementBoundarySimilarity;
  }

  double? _alternativeConsensus(
    TranscriptHypothesis baseline,
    String refinementText,
  ) {
    final alternatives = baseline.alternatives
        .where((candidate) => candidate.text.trim().isNotEmpty)
        .toList(growable: false);
    if (alternatives.length < 2) {
      return null;
    }

    double? bestSimilarity;
    for (final candidate in alternatives.take(
      maximumAlternativeConsensusRank,
    )) {
      final similarity = _characterSimilarity(
        _comparisonText(candidate.text),
        refinementText,
      );
      if (similarity >= minimumAlternativeConsensusSimilarity &&
          (bestSimilarity == null || similarity > bestSimilarity)) {
        bestSimilarity = similarity;
      }
    }
    return bestSimilarity;
  }
}

bool _hasRepeatedTokenRun(List<String> tokens, int maximumRun) {
  var previous = '';
  var run = 0;
  for (final token in tokens) {
    if (token == previous) {
      run += 1;
    } else {
      previous = token;
      run = 1;
    }
    if (run > maximumRun) {
      return true;
    }
  }
  return false;
}

TranscriptHypothesis _asFinal(TranscriptHypothesis hypothesis) {
  return TranscriptHypothesis(
    rawText: hypothesis.rawText,
    displayText: hypothesis.displayText,
    locale: hypothesis.locale,
    model: hypothesis.model,
    confidence: hypothesis.confidence,
    isFinal: true,
    alternatives: hypothesis.alternatives,
  );
}

String _comparisonText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670\u06D6-\u06ED]'), '')
      .replaceAll(RegExp(r'[،؛؟!?.ـ_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

double _characterSimilarity(String first, String second) {
  if (first == second) {
    return 1;
  }
  if (first.isEmpty || second.isEmpty) {
    return 0;
  }
  final previous = List<int>.generate(second.length + 1, (index) => index);
  final current = List<int>.filled(second.length + 1, 0);
  for (var firstIndex = 1; firstIndex <= first.length; firstIndex += 1) {
    current[0] = firstIndex;
    for (var secondIndex = 1; secondIndex <= second.length; secondIndex += 1) {
      final substitutionCost =
          first.codeUnitAt(firstIndex - 1) == second.codeUnitAt(secondIndex - 1)
          ? 0
          : 1;
      current[secondIndex] = _minimumOfThree(
        current[secondIndex - 1] + 1,
        previous[secondIndex] + 1,
        previous[secondIndex - 1] + substitutionCost,
      );
    }
    for (var index = 0; index < previous.length; index += 1) {
      previous[index] = current[index];
    }
  }
  final maximumLength = first.length > second.length
      ? first.length
      : second.length;
  return 1 - previous[second.length] / maximumLength;
}

int _minimumOfThree(int first, int second, int third) {
  final firstTwo = first < second ? first : second;
  return firstTwo < third ? firstTwo : third;
}

int _minimumOfTwo(int first, int second) => first < second ? first : second;
