import 'dart:async';
import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/application/default_transcription_session.dart';
import 'package:aurisia_mobile/features/transcription/domain/model_descriptor.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/speaker_attribution_engine.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/speech_turn_source.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/transcription_engine.dart';
import 'package:aurisia_mobile/features/transcription/domain/speaker_attribution.dart';
import 'package:aurisia_mobile/features/transcription/domain/speech_turn.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcript_hypothesis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'composes transcription and speaker attribution without adapter coupling',
    () async {
      final startedAt = DateTime.utc(2026, 1, 1, 12);
      final turn = SpeechTurn(
        id: 'turn-1',
        streamId: 'stream-1',
        startedAt: startedAt,
        endedAt: startedAt.add(const Duration(seconds: 1)),
        sampleRateHz: 16000,
        channels: 1,
        samples: Float32List.fromList([0]),
      );
      final source = _SpeechSource([turn]);
      final transcription = _TranscriptionEngine();
      final speakers = _SpeakerEngine();
      final session = DefaultTranscriptionSession(
        source: source,
        transcriptionEngine: transcription,
        speakerEngine: speakers,
      );

      final events = await session.start().toList();

      expect(events, hasLength(1));
      expect(events.single.displayText, 'نمشي للفارماسي وإيجا');
      expect(events.single.speakerId, 'speaker-cluster-a');
      expect(events.single.speakerIndex, 1);
      expect(transcription.lastTurn, same(turn));
      expect(speakers.lastTurn, same(turn));
      expect(speakers.resetCount, 1);
    },
  );

  test('does not publish empty recognition output', () async {
    final turn = SpeechTurn(
      id: 'turn-empty',
      streamId: 'stream-1',
      startedAt: DateTime.utc(2026),
      endedAt: DateTime.utc(2026),
      sampleRateHz: 16000,
      channels: 1,
      samples: Float32List(0),
    );
    final session = DefaultTranscriptionSession(
      source: _SpeechSource([turn]),
      transcriptionEngine: _TranscriptionEngine(text: '  '),
      speakerEngine: _SpeakerEngine(),
    );

    expect(await session.start().toList(), isEmpty);
  });

  test('bounds pending turns and drops the oldest under overload', () async {
    final turns = List<SpeechTurn>.generate(5, (index) => _turn(index));
    final transcription = _GatedTranscriptionEngine();
    final session = DefaultTranscriptionSession(
      source: _SpeechSource(turns),
      transcriptionEngine: transcription,
      speakerEngine: _SpeakerEngine(),
      maximumPendingTurns: 2,
    );

    final events = session.start().toList();
    await transcription.firstTurnStarted.future;
    await Future<void>.delayed(Duration.zero);
    transcription.releaseFirstTurn.complete();

    expect((await events).map((event) => event.eventId), <String>[
      'turn-0',
      'turn-3',
      'turn-4',
    ]);
    expect(session.droppedTurnCount, 2);
  });
}

SpeechTurn _turn(int index) {
  final startedAt = DateTime.utc(2026).add(Duration(seconds: index));
  return SpeechTurn(
    id: 'turn-$index',
    streamId: 'stream-1',
    startedAt: startedAt,
    endedAt: startedAt.add(const Duration(seconds: 1)),
    sampleRateHz: 16000,
    channels: 1,
    samples: Float32List.fromList([index.toDouble()]),
  );
}

class _SpeechSource implements SpeechTurnSource {
  _SpeechSource(this.turns);

  final List<SpeechTurn> turns;
  bool stopped = false;

  @override
  Stream<SpeechTurn> start() => Stream.fromIterable(turns);

  @override
  Future<void> stop() async {
    stopped = true;
  }

  @override
  Future<void> close() => stop();
}

class _TranscriptionEngine implements TranscriptionEngine {
  _TranscriptionEngine({this.text = 'نمشي للفارماسي وإيجا'});

  final String text;
  SpeechTurn? lastTurn;

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    lastTurn = turn;
    return TranscriptHypothesis(
      rawText: text,
      displayText: text,
      locale: 'aeb-TN',
      model: const ModelDescriptor(
        id: 'fake-asr',
        version: '1',
        runtime: 'fake',
      ),
    );
  }

  @override
  Future<void> close() async {}
}

class _GatedTranscriptionEngine implements TranscriptionEngine {
  final Completer<void> firstTurnStarted = Completer<void>();
  final Completer<void> releaseFirstTurn = Completer<void>();
  var _calls = 0;

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    _calls += 1;
    if (_calls == 1) {
      firstTurnStarted.complete();
      await releaseFirstTurn.future;
    }
    return TranscriptHypothesis(
      rawText: turn.id,
      displayText: turn.id,
      locale: 'aeb-TN',
      model: const ModelDescriptor(id: 'fake', version: '1', runtime: 'fake'),
    );
  }

  @override
  Future<void> close() async {}
}

class _SpeakerEngine implements SpeakerAttributionEngine {
  SpeechTurn? lastTurn;
  int resetCount = 0;

  @override
  Future<SpeakerAttribution> attribute(SpeechTurn turn) async {
    lastTurn = turn;
    return const SpeakerAttribution(
      speakerId: 'speaker-cluster-a',
      speakerIndex: 1,
      confidence: 0.85,
    );
  }

  @override
  Future<void> reset() async {
    resetCount += 1;
  }

  @override
  Future<void> close() async {}
}
