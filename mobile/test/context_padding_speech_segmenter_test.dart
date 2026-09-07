import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/application/context_padding_speech_segmenter.dart';
import 'package:aurisia_mobile/features/transcription/domain/pcm_audio_frame.dart';
import 'package:aurisia_mobile/features/transcription/domain/ports/speech_segmenter.dart';
import 'package:aurisia_mobile/features/transcription/domain/speech_turn.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('restores real leading and trailing PCM around a VAD turn', () async {
    final epoch = DateTime.utc(2026);
    final delegate = _MiddleFrameSegmenter(epoch);
    final segmenter = ContextPaddingSpeechSegmenter(
      segmenter: delegate,
      leadingPadding: const Duration(milliseconds: 100),
      trailingPadding: const Duration(milliseconds: 100),
      historyDuration: const Duration(seconds: 1),
    );
    await segmenter.reset();

    expect(segmenter.acceptFrame(_frame(epoch, 0, 1)), isEmpty);
    expect(segmenter.acceptFrame(_frame(epoch, 1, 2)), isEmpty);
    final turns = segmenter.acceptFrame(_frame(epoch, 2, 3)).toList();

    expect(turns, hasLength(1));
    final turn = turns.single;
    expect(turn.samples, hasLength(4800));
    expect(turn.samples[0], 1);
    expect(turn.samples[1600], 2);
    expect(turn.samples[3200], 3);
    expect(turn.startedAt, epoch);
    expect(turn.endedAt, epoch.add(const Duration(milliseconds: 300)));

    await segmenter.close();
    expect(delegate.closed, isTrue);
  });

  test('falls back to the original turn if retained history is incomplete', () {
    final epoch = DateTime.utc(2026);
    final original = SpeechTurn(
      id: 'turn-1',
      streamId: 'stream-1',
      startedAt: epoch,
      endedAt: epoch.add(const Duration(milliseconds: 100)),
      sampleRateHz: 16000,
      channels: 1,
      samples: Float32List(1600),
    );
    final segmenter = ContextPaddingSpeechSegmenter(
      segmenter: _ImmediateSegmenter(original),
      leadingPadding: const Duration(milliseconds: 100),
      trailingPadding: const Duration(milliseconds: 100),
      historyDuration: const Duration(seconds: 1),
    );

    final turns = segmenter
        .acceptFrame(_frame(epoch.add(const Duration(seconds: 1)), 0, 4))
        .toList();

    expect(turns.single.samples, hasLength(1600));
    expect(turns.single.startedAt, original.startedAt);
  });
}

PcmAudioFrame _frame(DateTime epoch, int sequence, double value) {
  return PcmAudioFrame(
    streamId: 'stream-1',
    sequence: sequence,
    capturedAt: epoch.add(Duration(milliseconds: (sequence + 1) * 100)),
    sampleRateHz: 16000,
    channels: 1,
    samples: Float32List.fromList(List<double>.filled(1600, value)),
  );
}

class _MiddleFrameSegmenter implements SpeechSegmenter {
  _MiddleFrameSegmenter(this.epoch);

  final DateTime epoch;
  bool closed = false;

  @override
  Iterable<SpeechTurn> acceptFrame(PcmAudioFrame frame) sync* {
    if (frame.sequence == 2) {
      yield SpeechTurn(
        id: 'turn-1',
        streamId: frame.streamId,
        startedAt: epoch.add(const Duration(milliseconds: 100)),
        endedAt: epoch.add(const Duration(milliseconds: 200)),
        sampleRateHz: frame.sampleRateHz,
        channels: 1,
        samples: Float32List.fromList(List<double>.filled(1600, 2)),
      );
    }
  }

  @override
  Iterable<SpeechTurn> flush() => const <SpeechTurn>[];

  @override
  Future<void> reset() async {}

  @override
  Future<void> close() async {
    closed = true;
  }
}

class _ImmediateSegmenter implements SpeechSegmenter {
  _ImmediateSegmenter(this.turn);

  final SpeechTurn turn;

  @override
  Iterable<SpeechTurn> acceptFrame(PcmAudioFrame frame) => <SpeechTurn>[turn];

  @override
  Iterable<SpeechTurn> flush() => const <SpeechTurn>[];

  @override
  Future<void> reset() async {}

  @override
  Future<void> close() async {}
}
