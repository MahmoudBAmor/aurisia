import '../domain/pcm_audio_frame.dart';
import '../domain/ports/transcript_text_normalizer.dart';
import '../domain/ports/transcription_engine.dart';
import '../domain/speech_turn.dart';
import '../domain/transcript_candidate.dart';
import '../domain/transcript_hypothesis.dart';

class NormalizingTranscriptionEngine implements TranscriptionEngine {
  const NormalizingTranscriptionEngine({
    required this.engine,
    required this.normalizer,
  });

  final TranscriptionEngine engine;
  final TranscriptTextNormalizer normalizer;

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    final hypothesis = await engine.transcribe(turn);
    return _normalizeHypothesis(hypothesis, normalizer);
  }

  @override
  Future<void> close() => engine.close();
}

class NormalizingStreamingTranscriptionEngine
    implements StreamingTranscriptionEngine {
  const NormalizingStreamingTranscriptionEngine({
    required this.engine,
    required this.normalizer,
  });

  final StreamingTranscriptionEngine engine;
  final TranscriptTextNormalizer normalizer;

  @override
  Future<void> startStream() => engine.startStream();

  @override
  Future<TranscriptHypothesis> acceptFrame(PcmAudioFrame frame) async {
    return _normalizeHypothesis(await engine.acceptFrame(frame), normalizer);
  }

  @override
  Future<TranscriptHypothesis> finishStream() async {
    return _normalizeHypothesis(await engine.finishStream(), normalizer);
  }

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    return _normalizeHypothesis(await engine.transcribe(turn), normalizer);
  }

  @override
  Future<void> close() => engine.close();
}

TranscriptHypothesis _normalizeHypothesis(
  TranscriptHypothesis hypothesis,
  TranscriptTextNormalizer normalizer,
) {
  return TranscriptHypothesis(
    rawText: hypothesis.rawText,
    displayText: normalizer.normalize(hypothesis.displayText),
    locale: hypothesis.locale,
    model: hypothesis.model,
    confidence: hypothesis.confidence,
    isFinal: hypothesis.isFinal,
    alternatives: hypothesis.alternatives
        .map(
          (candidate) => TranscriptCandidate(
            text: normalizer.normalize(candidate.text),
            confidence: candidate.confidence,
          ),
        )
        .toList(growable: false),
  );
}
