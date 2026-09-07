import 'dart:async';
import 'dart:typed_data';

import '../../domain/ports/speech_turn_source.dart';
import '../../domain/speech_turn.dart';

class DemoSpeechTurnSource implements SpeechTurnSource {
  DemoSpeechTurnSource({this.interval = const Duration(milliseconds: 1200)});

  final Duration interval;
  bool _running = false;
  int _sequence = 0;

  @override
  Stream<SpeechTurn> start() async* {
    if (_running) {
      throw StateError('The demo source is already running.');
    }
    _running = true;

    while (_running) {
      await Future<void>.delayed(interval);
      if (!_running) {
        break;
      }

      final sequence = _sequence++;
      final endedAt = DateTime.now();
      yield SpeechTurn(
        id: 'demo-$sequence',
        streamId: 'demo-session',
        startedAt: endedAt.subtract(const Duration(milliseconds: 900)),
        endedAt: endedAt,
        sampleRateHz: 16000,
        channels: 1,
        samples: Float32List(0),
      );
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
  }

  @override
  Future<void> close() => stop();
}
