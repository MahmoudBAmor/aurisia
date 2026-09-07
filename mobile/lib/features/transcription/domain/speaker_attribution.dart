class SpeakerAttribution {
  const SpeakerAttribution({
    required this.speakerId,
    required this.speakerIndex,
    this.confidence,
  }) : assert(speakerIndex >= 0);

  final String speakerId;
  final int speakerIndex;
  final double? confidence;
}
