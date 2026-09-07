import 'model_descriptor.dart';
import 'transcript_candidate.dart';

class TranscriptHypothesis {
  const TranscriptHypothesis({
    required this.rawText,
    required this.displayText,
    required this.locale,
    required this.model,
    this.confidence,
    this.isFinal = true,
    this.alternatives = const <TranscriptCandidate>[],
  });

  final String rawText;
  final String displayText;
  final String locale;
  final ModelDescriptor model;
  final double? confidence;
  final bool isFinal;
  final List<TranscriptCandidate> alternatives;
}
