import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/infrastructure/speaker/online_speaker_clusterer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'keeps similar turns and confirms a different voice before splitting',
    () {
      final clusterer = OnlineSpeakerClusterer(similarityThreshold: 0.8);

      final first = clusterer.attribute(Float32List.fromList([1, 0, 0]));
      final similar = clusterer.attribute(
        Float32List.fromList([0.99, 0.05, 0]),
      );
      final firstDifferent = clusterer.attribute(
        Float32List.fromList([0, 1, 0]),
      );
      final confirmedDifferent = clusterer.attribute(
        Float32List.fromList([0, 0.99, 0.05]),
      );
      final repeatedDifferent = clusterer.attribute(
        Float32List.fromList([0.05, 0.99, 0]),
      );

      expect(first.speakerIndex, 0);
      expect(similar.speakerIndex, 0);
      expect(firstDifferent.speakerIndex, 0);
      expect(confirmedDifferent.speakerIndex, 0);
      expect(repeatedDifferent.speakerIndex, 1);
      expect(clusterer.speakerCount, 2);
    },
  );

  test('does not create a speaker from one inconsistent observation', () {
    final clusterer = OnlineSpeakerClusterer();

    clusterer.attribute(Float32List.fromList([1, 0, 0]));
    final outlier = clusterer.attribute(Float32List.fromList([0.45, 0.89, 0]));
    final recovered = clusterer.attribute(Float32List.fromList([0.95, 0.2, 0]));

    expect(outlier.speakerIndex, 0);
    expect(recovered.speakerIndex, 0);
    expect(clusterer.speakerCount, 1);
  });

  test('uses temporal hysteresis between two similar known voices', () {
    final clusterer = OnlineSpeakerClusterer(
      similarityThreshold: 0.65,
      pendingSpeakerSimilarityThreshold: 0.9,
      speakerSwitchMargin: 0.1,
      newSpeakerConfirmationCount: 2,
    );

    clusterer.attribute(Float32List.fromList([1, 0, 0]));
    clusterer.attribute(Float32List.fromList([0, 1, 0]));
    clusterer.attribute(Float32List.fromList([0.05, 0.99, 0]));
    final second = clusterer.attributeWithDecision(
      Float32List.fromList([0.02, 1, 0]),
    );
    final ambiguous = clusterer.attributeWithDecision(
      Float32List.fromList([0.73, 0.68, 0]),
    );

    expect(second.attribution.speakerIndex, 1);
    expect(ambiguous.attribution.speakerIndex, 1);
    expect(ambiguous.reason, SpeakerClusteringReason.continuityProtected);
  });

  test('confirms a new voice across alternating speakers', () {
    final clusterer = OnlineSpeakerClusterer(
      similarityThreshold: 0.8,
      newSpeakerConfirmationCount: 2,
    );

    clusterer.attribute(Float32List.fromList([1, 0, 0]));
    final firstSecondVoice = clusterer.attribute(
      Float32List.fromList([0, 1, 0]),
    );
    final originalVoice = clusterer.attribute(
      Float32List.fromList([0.99, 0.05, 0]),
    );
    final confirmedSecondVoice = clusterer.attribute(
      Float32List.fromList([0.05, 0.99, 0]),
    );

    expect(firstSecondVoice.speakerIndex, 0);
    expect(originalVoice.speakerIndex, 0);
    expect(confirmedSecondVoice.speakerIndex, 1);
    expect(clusterer.speakerCount, 2);
  });

  test('tracks two new voice candidates without mixing them', () {
    final clusterer = OnlineSpeakerClusterer(
      similarityThreshold: 0.8,
      newSpeakerConfirmationCount: 2,
    );

    clusterer.attribute(Float32List.fromList([1, 0, 0]));
    clusterer.attribute(Float32List.fromList([0, 1, 0]));
    clusterer.attribute(Float32List.fromList([0, 0, 1]));
    final secondVoice = clusterer.attribute(
      Float32List.fromList([0.05, 0.99, 0]),
    );
    final thirdVoice = clusterer.attribute(
      Float32List.fromList([0, 0.05, 0.99]),
    );

    expect(secondVoice.speakerIndex, 1);
    expect(thirdVoice.speakerIndex, 2);
    expect(clusterer.speakerCount, 3);
  });

  test('expires an old unconfirmed voice candidate', () {
    final clusterer = OnlineSpeakerClusterer(
      similarityThreshold: 0.8,
      newSpeakerConfirmationCount: 2,
      pendingSpeakerMaximumAge: 2,
    );

    clusterer.attribute(Float32List.fromList([1, 0, 0]));
    clusterer.attribute(Float32List.fromList([0, 1, 0]));
    clusterer.attribute(Float32List.fromList([1, 0, 0]));
    clusterer.attribute(Float32List.fromList([1, 0, 0]));
    clusterer.attribute(Float32List.fromList([1, 0, 0]));
    final oldVoiceReturns = clusterer.attribute(
      Float32List.fromList([0.05, 0.99, 0]),
    );

    expect(oldVoiceReturns.speakerIndex, 0);
    expect(clusterer.speakerCount, 1);
  });

  test('reuses the last speaker when no reliable embedding is available', () {
    final clusterer = OnlineSpeakerClusterer();

    expect(clusterer.reuseLastSpeaker().speakerIndex, 0);
    clusterer.attribute(Float32List.fromList([1, 0]));
    clusterer.attribute(Float32List.fromList([0, 1]));

    expect(clusterer.reuseLastSpeaker().speakerIndex, 0);
    expect(clusterer.speakerCount, 1);
  });

  test('reset forgets session-local speakers', () {
    final clusterer = OnlineSpeakerClusterer();
    clusterer.attribute(Float32List.fromList([1, 0]));
    clusterer.attribute(Float32List.fromList([0, 1]));

    clusterer.reset();
    final firstAfterReset = clusterer.attribute(Float32List.fromList([0, 1]));

    expect(firstAfterReset.speakerIndex, 0);
    expect(clusterer.speakerCount, 1);
  });

  test('respects the configured maximum speaker count', () {
    final clusterer = OnlineSpeakerClusterer(
      similarityThreshold: 0.9,
      maximumSpeakers: 2,
    );
    clusterer.attribute(Float32List.fromList([1, 0, 0]));
    clusterer.attribute(Float32List.fromList([0, 1, 0]));
    clusterer.attribute(Float32List.fromList([0, 0.99, 0.05]));
    clusterer.attribute(Float32List.fromList([0.05, 0.99, 0]));
    clusterer.attribute(Float32List.fromList([0, 0, 1]));
    clusterer.attribute(Float32List.fromList([0.05, 0, 0.99]));
    final thirdVoice = clusterer.attribute(
      Float32List.fromList([0, 0.05, 0.99]),
    );

    expect(clusterer.speakerCount, 2);
    expect(thirdVoice.speakerIndex, anyOf(0, 1));
  });
}
