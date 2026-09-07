import 'dart:math';
import 'dart:typed_data';

import '../../domain/speaker_attribution.dart';

class OnlineSpeakerClusterer {
  OnlineSpeakerClusterer({
    this.similarityThreshold = 0.5,
    double? pendingSpeakerSimilarityThreshold,
    this.speakerSwitchMargin = 0.08,
    this.maximumSpeakers = 6,
    this.newSpeakerConfirmationCount = 3,
    this.pendingSpeakerMaximumAge = 8,
  }) : pendingSpeakerSimilarityThreshold =
           pendingSpeakerSimilarityThreshold ?? max(similarityThreshold, 0.7) {
    if (similarityThreshold < -1 || similarityThreshold > 1) {
      throw ArgumentError.value(similarityThreshold, 'similarityThreshold');
    }
    if (maximumSpeakers <= 0) {
      throw ArgumentError.value(maximumSpeakers, 'maximumSpeakers');
    }
    if (this.pendingSpeakerSimilarityThreshold < similarityThreshold ||
        this.pendingSpeakerSimilarityThreshold > 1) {
      throw ArgumentError.value(
        this.pendingSpeakerSimilarityThreshold,
        'pendingSpeakerSimilarityThreshold',
        'must be between similarityThreshold and 1',
      );
    }
    if (speakerSwitchMargin < 0 || speakerSwitchMargin > 2) {
      throw ArgumentError.value(
        speakerSwitchMargin,
        'speakerSwitchMargin',
        'must be between 0 and 2',
      );
    }
    if (newSpeakerConfirmationCount < 2) {
      throw ArgumentError.value(
        newSpeakerConfirmationCount,
        'newSpeakerConfirmationCount',
        'must be at least 2',
      );
    }
    if (pendingSpeakerMaximumAge < newSpeakerConfirmationCount) {
      throw ArgumentError.value(
        pendingSpeakerMaximumAge,
        'pendingSpeakerMaximumAge',
        'must be at least newSpeakerConfirmationCount',
      );
    }
  }

  final double similarityThreshold;
  final double pendingSpeakerSimilarityThreshold;
  final double speakerSwitchMargin;
  final int maximumSpeakers;
  final int newSpeakerConfirmationCount;
  final int pendingSpeakerMaximumAge;
  final List<_SpeakerCluster> _clusters = [];
  final List<_PendingSpeakerCluster> _pendingSpeakers = [];
  int? _lastSpeakerIndex;
  int _turnSequence = 0;

  int get speakerCount => _clusters.length;

  SpeakerAttribution attribute(Float32List embedding) =>
      attributeWithDecision(embedding).attribution;

  SpeakerClusteringDecision attributeWithDecision(Float32List embedding) {
    _turnSequence += 1;
    final normalized = _normalize(embedding);
    if (_clusters.isEmpty) {
      return SpeakerClusteringDecision(
        attribution: _addSpeaker(normalized),
        reason: SpeakerClusteringReason.initialSpeaker,
        bestSimilarity: 1,
        selectedSimilarity: 1,
        createdSpeaker: true,
      );
    }

    var bestIndex = 0;
    var bestSimilarity = -1.0;
    final similarities = <double>[];
    for (var index = 0; index < _clusters.length; index += 1) {
      final similarity = _dot(normalized, _clusters[index].centroid);
      similarities.add(similarity);
      if (similarity > bestSimilarity) {
        bestSimilarity = similarity;
        bestIndex = index;
      }
    }

    if (bestSimilarity >= similarityThreshold) {
      _discardStalePendingSpeakers();
      final lastIndex = _lastSpeakerIndex;
      if (lastIndex != null &&
          bestIndex != lastIndex &&
          bestSimilarity - similarities[lastIndex] < speakerSwitchMargin) {
        final lastSimilarity = similarities[lastIndex];
        if (lastSimilarity >= similarityThreshold) {
          _clusters[lastIndex].include(normalized);
        }
        _lastSpeakerIndex = lastIndex;
        return SpeakerClusteringDecision(
          attribution: _attribution(lastIndex, lastSimilarity),
          reason: SpeakerClusteringReason.continuityProtected,
          bestSimilarity: bestSimilarity,
          selectedSimilarity: lastSimilarity,
        );
      }
      _clusters[bestIndex].include(normalized);
      _lastSpeakerIndex = bestIndex;
      return SpeakerClusteringDecision(
        attribution: _attribution(bestIndex, bestSimilarity),
        reason: SpeakerClusteringReason.matchedSpeaker,
        bestSimilarity: bestSimilarity,
        selectedSimilarity: bestSimilarity,
      );
    }

    var reason = SpeakerClusteringReason.pendingNewSpeaker;
    if (_clusters.length < maximumSpeakers) {
      _discardStalePendingSpeakers();
      final pending = _bestPendingSpeaker(normalized);
      if (pending == null) {
        _rememberPendingSpeaker(normalized);
      } else {
        pending.includeAt(normalized, _turnSequence);
        if (pending.observations >= newSpeakerConfirmationCount) {
          _pendingSpeakers.remove(pending);
          final attribution = _addSpeaker(pending.centroid);
          _discardPendingSpeakersMatching(pending.centroid);
          return SpeakerClusteringDecision(
            attribution: attribution,
            reason: SpeakerClusteringReason.confirmedNewSpeaker,
            bestSimilarity: bestSimilarity,
            selectedSimilarity: 1,
            createdSpeaker: true,
          );
        }
      }
    } else {
      reason = SpeakerClusteringReason.maximumSpeakersReached;
    }

    // One outlying turn is not enough evidence to change the visible speaker.
    // Keep temporal continuity without contaminating an existing centroid.
    final fallbackIndex = _lastSpeakerIndex ?? bestIndex;
    return SpeakerClusteringDecision(
      attribution: _attribution(fallbackIndex, similarities[fallbackIndex]),
      reason: reason,
      bestSimilarity: bestSimilarity,
      selectedSimilarity: similarities[fallbackIndex],
    );
  }

  SpeakerAttribution reuseLastSpeaker() {
    final index = _lastSpeakerIndex ?? 0;
    return SpeakerAttribution(
      speakerId: 'session-speaker-$index',
      speakerIndex: index,
    );
  }

  void reset() {
    _clusters.clear();
    _pendingSpeakers.clear();
    _lastSpeakerIndex = null;
    _turnSequence = 0;
  }

  _PendingSpeakerCluster? _bestPendingSpeaker(Float32List embedding) {
    _PendingSpeakerCluster? best;
    var bestSimilarity = -1.0;
    for (final candidate in _pendingSpeakers) {
      final similarity = _dot(embedding, candidate.centroid);
      if (similarity >= pendingSpeakerSimilarityThreshold &&
          similarity > bestSimilarity) {
        best = candidate;
        bestSimilarity = similarity;
      }
    }
    return best;
  }

  void _rememberPendingSpeaker(Float32List embedding) {
    final capacity = maximumSpeakers - _clusters.length;
    if (capacity <= 0) {
      return;
    }
    if (_pendingSpeakers.length >= capacity) {
      _pendingSpeakers.sort((first, second) {
        final observationOrder = first.observations.compareTo(
          second.observations,
        );
        return observationOrder != 0
            ? observationOrder
            : first.lastSeenSequence.compareTo(second.lastSeenSequence);
      });
      _pendingSpeakers.removeAt(0);
    }
    _pendingSpeakers.add(
      _PendingSpeakerCluster(embedding, lastSeenSequence: _turnSequence),
    );
  }

  void _discardStalePendingSpeakers() {
    _pendingSpeakers.removeWhere(
      (candidate) =>
          _turnSequence - candidate.lastSeenSequence > pendingSpeakerMaximumAge,
    );
  }

  void _discardPendingSpeakersMatching(Float32List confirmedSpeaker) {
    _pendingSpeakers.removeWhere(
      (candidate) =>
          _dot(candidate.centroid, confirmedSpeaker) >=
          pendingSpeakerSimilarityThreshold,
    );
  }

  SpeakerAttribution _addSpeaker(Float32List embedding) {
    final index = _clusters.length;
    _clusters.add(_SpeakerCluster(embedding));
    _lastSpeakerIndex = index;
    return SpeakerAttribution(
      speakerId: 'session-speaker-$index',
      speakerIndex: index,
      confidence: 1,
    );
  }

  SpeakerAttribution _attribution(int index, double similarity) {
    return SpeakerAttribution(
      speakerId: 'session-speaker-$index',
      speakerIndex: index,
      confidence: similarity.clamp(0.0, 1.0).toDouble(),
    );
  }
}

enum SpeakerClusteringReason {
  initialSpeaker,
  matchedSpeaker,
  continuityProtected,
  pendingNewSpeaker,
  confirmedNewSpeaker,
  maximumSpeakersReached,
}

class SpeakerClusteringDecision {
  const SpeakerClusteringDecision({
    required this.attribution,
    required this.reason,
    required this.bestSimilarity,
    required this.selectedSimilarity,
    this.createdSpeaker = false,
  });

  final SpeakerAttribution attribution;
  final SpeakerClusteringReason reason;
  final double bestSimilarity;
  final double selectedSimilarity;
  final bool createdSpeaker;
}

class _SpeakerCluster {
  _SpeakerCluster(Float32List initial)
    : centroid = Float32List.fromList(initial);

  Float32List centroid;
  int observations = 1;

  void include(Float32List embedding) {
    final updated = Float32List(centroid.length);
    for (var index = 0; index < centroid.length; index += 1) {
      updated[index] =
          (centroid[index] * observations + embedding[index]) /
          (observations + 1);
    }
    centroid = _normalize(updated);
    observations += 1;
  }
}

class _PendingSpeakerCluster extends _SpeakerCluster {
  _PendingSpeakerCluster(super.initial, {required this.lastSeenSequence});

  int lastSeenSequence;

  void includeAt(Float32List embedding, int sequence) {
    super.include(embedding);
    lastSeenSequence = sequence;
  }
}

Float32List _normalize(Float32List value) {
  if (value.isEmpty) {
    throw ArgumentError.value(value, 'embedding', 'must not be empty');
  }
  var squaredNorm = 0.0;
  for (final element in value) {
    squaredNorm += element * element;
  }
  final norm = sqrt(squaredNorm);
  if (norm == 0) {
    throw ArgumentError.value(value, 'embedding', 'must not have zero norm');
  }
  return Float32List.fromList(value.map((element) => element / norm).toList());
}

double _dot(Float32List first, Float32List second) {
  if (first.length != second.length) {
    throw ArgumentError('Speaker embeddings must have the same dimensions.');
  }
  var result = 0.0;
  for (var index = 0; index < first.length; index += 1) {
    result += first[index] * second[index];
  }
  return result;
}
