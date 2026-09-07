import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/application/preprocessing_transcription_engine.dart';
import 'package:aurisia_mobile/features/transcription/domain/model_descriptor.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/speech_turn_preprocessor.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/transcription_engine.dart';
import 'package:aurisia_mobile/features/transcription/domain/speech_turn.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcript_hypothesis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('transforms only the turn passed to the decorated engine', () async {
    final delegate = _RecordingEngine();
    final engine = PreprocessingTranscriptionEngine(
      engine: delegate,
      preprocessor: const _HalfLengthPreprocessor(),
    );
    final turn = _turn(Float32List(1600));

    await engine.transcribe(turn);
    await engine.close();

    expect(turn.samples, hasLength(1600));
    expect(delegate.received?.samples, hasLength(800));
    expect(delegate.closed, isTrue);
  });
}

SpeechTurn _turn(Float32List samples) {
  final now = DateTime.utc(2026);
  return SpeechTurn(
    id: 'turn-1',
    streamId: 'stream-1',
    startedAt: now,
    endedAt: now.add(const Duration(milliseconds: 100)),
    sampleRateHz: 16000,
    channels: 1,
    samples: samples,
  );
}

class _HalfLengthPreprocessor implements SpeechTurnPreprocessor {
  const _HalfLengthPreprocessor();

  @override
  SpeechTurn process(SpeechTurn turn) {
    return SpeechTurn(
      id: turn.id,
      streamId: turn.streamId,
      startedAt: turn.startedAt,
      endedAt: turn.endedAt,
      sampleRateHz: turn.sampleRateHz,
      channels: turn.channels,
      samples: Float32List(turn.samples.length ~/ 2),
    );
  }
}

class _RecordingEngine implements TranscriptionEngine {
  SpeechTurn? received;
  bool closed = false;

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    received = turn;
    return const TranscriptHypothesis(
      rawText: '',
      displayText: '',
      locale: 'ar',
      model: ModelDescriptor(id: 'fake', version: '1', runtime: 'fake'),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
