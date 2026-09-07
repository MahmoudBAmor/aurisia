import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/application/streaming_transcription_session.dart';
import 'package:aurisia_mobile/features/transcription/domain/model_descriptor.dart';
import 'package:aurisia_mobile/features/transcription/domain/pcm_audio_frame.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/pcm_audio_input.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/speaker_attribution_engine.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/speech_segmenter.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/transcription_engine.dart';
import 'package:aurisia_mobile/features/transcription/domain/speaker_attribution.dart';
import 'package:aurisia_mobile/features/transcription/domain/speech_turn.dart';
import 'package:aurisia_mobile/features/transcription/domain/transcript_hypothesis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'publishes partial text before asynchronously correcting its speaker',
    () async {
      final capturedAt = DateTime.now();
      final frames = <PcmAudioFrame>[
        _frame(sequence: 0, capturedAt: capturedAt),
        _frame(
          sequence: 1,
          capturedAt: capturedAt.add(const Duration(milliseconds: 100)),
        ),
      ];
      final turn = SpeechTurn(
        id: 'vad-turn-1',
        streamId: 'mobile-test',
        startedAt: capturedAt.subtract(const Duration(milliseconds: 100)),
        endedAt: capturedAt.add(const Duration(milliseconds: 100)),
        sampleRateHz: 16000,
        channels: 1,
        samples: Float32List(3200),
      );
      final asr = _StreamingEngine();
      final session = StreamingDefaultTranscriptionSession(
        audioInput: _AudioInput(frames),
        segmenter: _FlushSegmenter(turn),
        transcriptionEngine: asr,
        speakerEngine: _SpeakerEngine(),
      );

      final events = await session.start().toList();

      expect(events.map((event) => event.eventId).toSet(), <String>{
        'mobile-test-live-0',
      });
      expect(events.first.displayText, 'السلام');
      expect(events.first.isFinal, isFalse);
      expect(events.first.speakerIndex, 0);
      expect(events.where((event) => event.isFinal), hasLength(2));
      expect(events[events.length - 2].speakerIndex, 0);
      expect(events.last.displayText, 'السلام عليكم ورحمة الله');
      expect(events.last.speakerIndex, 2);
      expect(asr.startCount, 1);
      expect(asr.finishCount, 1);

      await session.close();
    },
  );

  test(
    'publishes a fast streaming result then a refined final result',
    () async {
      final capturedAt = DateTime.now();
      final turn = SpeechTurn(
        id: 'vad-turn-refined',
        streamId: 'mobile-test',
        startedAt: capturedAt,
        endedAt: capturedAt.add(const Duration(milliseconds: 200)),
        sampleRateHz: 16000,
        channels: 1,
        samples: Float32List(3200),
      );
      final finalAsr = _FinalEngine();
      final session = StreamingDefaultTranscriptionSession(
        audioInput: _AudioInput(<PcmAudioFrame>[
          _frame(sequence: 0, capturedAt: capturedAt),
        ]),
        segmenter: _FlushSegmenter(turn),
        transcriptionEngine: _StreamingEngine(),
        finalTranscriptionEngine: finalAsr,
        speakerEngine: _SpeakerEngine(),
      );

      final events = await session.start().toList();

      expect(events.where((event) => event.isFinal), hasLength(3));
      expect(events[events.length - 2].displayText, 'السلام عليكم ورحمة الله');
      expect(events.last.displayText, 'السلام عليكم ورحمة الله وبركاته');
      expect(events.last.model.id, 'fake-final-asr');

      await session.close();
      expect(finalAsr.closed, isTrue);
    },
  );

  test(
    'publishes a sermon correction beyond the generic freshness window',
    () async {
      final endedAt = DateTime.now().subtract(
        const Duration(milliseconds: 4500),
      );
      final turn = SpeechTurn(
        id: 'vad-turn-prolonged-sermon',
        streamId: 'mobile-test',
        startedAt: endedAt.subtract(const Duration(milliseconds: 200)),
        endedAt: endedAt,
        sampleRateHz: 16000,
        channels: 1,
        samples: Float32List(3200),
      );
      final session = StreamingDefaultTranscriptionSession(
        audioInput: _AudioInput(<PcmAudioFrame>[
          _frame(sequence: 0, capturedAt: endedAt),
        ]),
        segmenter: _FlushSegmenter(turn),
        transcriptionEngine: _StreamingEngine(),
        finalTranscriptionEngine: _FinalEngine(),
        speakerEngine: _SpeakerEngine(),
        maximumRefinementAge: const Duration(seconds: 8),
      );

      final events = await session.start().toList();

      expect(events.last.model.id, 'fake-final-asr');
      expect(events.last.displayText, 'السلام عليكم ورحمة الله وبركاته');
      await session.close();
    },
  );

  test(
    'does not replace a stable partial with a weak divergent final',
    () async {
      final capturedAt = DateTime.now();
      final turn = SpeechTurn(
        id: 'vad-turn-regression',
        streamId: 'mobile-test',
        startedAt: capturedAt,
        endedAt: capturedAt.add(const Duration(milliseconds: 300)),
        sampleRateHz: 16000,
        channels: 1,
        samples: Float32List(4800),
      );
      final session = StreamingDefaultTranscriptionSession(
        audioInput: _AudioInput(<PcmAudioFrame>[
          _frame(sequence: 0, capturedAt: capturedAt),
          _frame(
            sequence: 1,
            capturedAt: capturedAt.add(const Duration(milliseconds: 100)),
          ),
          _frame(
            sequence: 2,
            capturedAt: capturedAt.add(const Duration(milliseconds: 200)),
          ),
        ]),
        segmenter: _FlushSegmenter(turn),
        transcriptionEngine: _RegressingStreamingEngine(),
        speakerEngine: _SpeakerEngine(),
      );

      final events = await session.start().toList();
      final finalEvents = events.where((event) => event.isFinal).toList();

      expect(finalEvents, hasLength(2));
      expect(
        finalEvents.map((event) => event.displayText),
        everyElement('نمشي للصيدلية و نرجع'),
      );

      await session.close();
    },
  );

  test(
    'bounds final-ASR backlog and keeps only the latest waiting turn',
    () async {
      final capturedAt = DateTime.now();
      final frames = List<PcmAudioFrame>.generate(
        3,
        (index) => _frame(
          sequence: index,
          capturedAt: capturedAt.add(Duration(milliseconds: index * 100)),
        ),
      );
      final finalAsr = _SlowFinalEngine();
      final session = StreamingDefaultTranscriptionSession(
        audioInput: _AudioInput(frames),
        segmenter: _TurnPerFrameSegmenter(),
        transcriptionEngine: _StreamingEngine(),
        finalTranscriptionEngine: finalAsr,
        speakerEngine: _SpeakerEngine(),
      );

      await session.start().toList();

      expect(finalAsr.transcribedTurnIds, <String>['turn-0', 'turn-2']);
      await session.close();
    },
  );
}

PcmAudioFrame _frame({required int sequence, required DateTime capturedAt}) {
  return PcmAudioFrame(
    streamId: 'mobile-test',
    sequence: sequence,
    capturedAt: capturedAt,
    sampleRateHz: 16000,
    channels: 1,
    samples: Float32List(1600),
  );
}

class _AudioInput implements PcmAudioInput {
  _AudioInput(this.frames);

  final List<PcmAudioFrame> frames;

  @override
  Stream<PcmAudioFrame> start() => Stream.fromIterable(frames);

  @override
  Future<void> stop() async {}

  @override
  Future<void> close() async {}
}

class _FlushSegmenter implements SpeechSegmenter {
  _FlushSegmenter(this.turn);

  final SpeechTurn turn;

  @override
  Iterable<SpeechTurn> acceptFrame(PcmAudioFrame frame) => const [];

  @override
  Iterable<SpeechTurn> flush() => <SpeechTurn>[turn];

  @override
  Future<void> reset() async {}

  @override
  Future<void> close() async {}
}

class _TurnPerFrameSegmenter implements SpeechSegmenter {
  @override
  Iterable<SpeechTurn> acceptFrame(PcmAudioFrame frame) sync* {
    yield SpeechTurn(
      id: 'turn-${frame.sequence}',
      streamId: frame.streamId,
      startedAt: frame.capturedAt.subtract(const Duration(milliseconds: 100)),
      endedAt: frame.capturedAt,
      sampleRateHz: frame.sampleRateHz,
      channels: frame.channels,
      samples: frame.samples,
    );
  }

  @override
  Iterable<SpeechTurn> flush() => const <SpeechTurn>[];

  @override
  Future<void> reset() async {}

  @override
  Future<void> close() async {}
}

class _StreamingEngine implements StreamingTranscriptionEngine {
  static const model = ModelDescriptor(
    id: 'fake-streaming-asr',
    version: '1',
    runtime: 'fake',
  );

  var startCount = 0;
  var finishCount = 0;
  var acceptedFrames = 0;

  @override
  Future<void> startStream() async {
    startCount += 1;
  }

  @override
  Future<TranscriptHypothesis> acceptFrame(PcmAudioFrame frame) async {
    acceptedFrames += 1;
    return TranscriptHypothesis(
      rawText: acceptedFrames == 1 ? 'السلام' : 'السلام عليكم',
      displayText: acceptedFrames == 1 ? 'السلام' : 'السلام عليكم',
      locale: 'ar',
      model: model,
      isFinal: false,
    );
  }

  @override
  Future<TranscriptHypothesis> finishStream() async {
    finishCount += 1;
    return const TranscriptHypothesis(
      rawText: 'السلام عليكم ورحمة الله',
      displayText: 'السلام عليكم ورحمة الله',
      locale: 'ar',
      model: model,
    );
  }

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {}
}

class _SpeakerEngine implements SpeakerAttributionEngine {
  @override
  Future<SpeakerAttribution> attribute(SpeechTurn turn) async {
    await Future<void>.delayed(Duration.zero);
    return const SpeakerAttribution(
      speakerId: 'session-speaker-2',
      speakerIndex: 2,
      confidence: 0.9,
    );
  }

  @override
  Future<void> reset() async {}

  @override
  Future<void> close() async {}
}

class _SlowFinalEngine implements TranscriptionEngine {
  final List<String> transcribedTurnIds = <String>[];

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    transcribedTurnIds.add(turn.id);
    if (transcribedTurnIds.length == 1) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    return const TranscriptHypothesis(
      rawText: 'نص مصحح',
      displayText: 'نص مصحح',
      locale: 'ar',
      model: ModelDescriptor(id: 'slow-final', version: '1', runtime: 'fake'),
    );
  }

  @override
  Future<void> close() async {}
}

class _RegressingStreamingEngine implements StreamingTranscriptionEngine {
  static const model = ModelDescriptor(
    id: 'regressing-streaming-asr',
    version: '1',
    runtime: 'fake',
  );

  @override
  Future<void> startStream() async {}

  @override
  Future<TranscriptHypothesis> acceptFrame(PcmAudioFrame frame) async {
    return const TranscriptHypothesis(
      rawText: 'نمشي للصيدلية و نرجع',
      displayText: 'نمشي للصيدلية و نرجع',
      locale: 'ar-TN',
      model: model,
      confidence: 0.86,
      isFinal: false,
    );
  }

  @override
  Future<TranscriptHypothesis> finishStream() async {
    return const TranscriptHypothesis(
      rawText: 'نمشي للمدرسة غدوة',
      displayText: 'نمشي للمدرسة غدوة',
      locale: 'ar-TN',
      model: model,
      confidence: 0.59,
    );
  }

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) {
    throw UnimplementedError();
  }

  @override
  Future<void> close() async {}
}

class _FinalEngine implements TranscriptionEngine {
  var closed = false;

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    return const TranscriptHypothesis(
      rawText: 'السلام عليكم ورحمة الله وبركاته',
      displayText: 'السلام عليكم ورحمة الله وبركاته',
      locale: 'ar',
      model: ModelDescriptor(
        id: 'fake-final-asr',
        version: '1',
        runtime: 'fake',
      ),
    );
  }

  @override
  Future<void> close() async {
    closed = true;
  }
}
