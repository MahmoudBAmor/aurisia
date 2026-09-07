import 'dart:async';
import 'dart:collection';

import '../domain/ports/speaker_attribution_engine.dart';
import '../domain/ports/speech_turn_source.dart';
import '../domain/ports/transcription_engine.dart';
import '../domain/ports/transcription_session.dart';
import '../domain/speech_turn.dart';
import '../domain/transcript_segment.dart';

class DefaultTranscriptionSession implements TranscriptionSession {
  DefaultTranscriptionSession({
    required this.source,
    required this.transcriptionEngine,
    required this.speakerEngine,
    this.maximumPendingTurns = 3,
  }) {
    if (maximumPendingTurns <= 0) {
      throw ArgumentError.value(maximumPendingTurns, 'maximumPendingTurns');
    }
  }

  final SpeechTurnSource source;
  final TranscriptionEngine transcriptionEngine;
  final SpeakerAttributionEngine speakerEngine;
  final int maximumPendingTurns;
  bool _running = false;
  bool _closed = false;
  Future<void>? _closeTask;
  Future<void>? _runTask;
  _BoundedSpeechTurnQueue? _pendingTurns;
  int _droppedTurnCount = 0;

  int get droppedTurnCount => _droppedTurnCount;

  @override
  Stream<TranscriptSegment> start() {
    if (_closed) {
      throw StateError('The transcription session is closed.');
    }
    if (_running) {
      throw StateError('The transcription session is already running.');
    }

    _running = true;
    _droppedTurnCount = 0;
    late final StreamController<TranscriptSegment> output;
    output = StreamController<TranscriptSegment>(
      onListen: () {
        _runTask = _run(output);
      },
      onCancel: _cancelFromListener,
    );
    return output.stream;
  }

  Future<void> _run(StreamController<TranscriptSegment> output) async {
    final queue = _BoundedSpeechTurnQueue(capacity: maximumPendingTurns);
    _pendingTurns = queue;
    Object? producerError;
    StackTrace? producerStackTrace;

    var producer = Future<void>.value();

    try {
      await speakerEngine.reset();
      producer = () async {
        try {
          await for (final turn in source.start()) {
            if (!_running) {
              break;
            }
            if (queue.add(turn)) {
              _droppedTurnCount += 1;
            }
          }
        } catch (error, stackTrace) {
          producerError = error;
          producerStackTrace = stackTrace;
        } finally {
          queue.close();
        }
      }();

      while (_running) {
        final turn = await queue.take();
        if (turn == null) {
          break;
        }
        if (!_running) {
          break;
        }

        final segment = await _process(turn);
        if (segment != null && _running && !output.isClosed) {
          output.add(segment);
        }
      }

      await producer;
      if (producerError != null) {
        Error.throwWithStackTrace(producerError!, producerStackTrace!);
      }
    } catch (error, stackTrace) {
      if (!output.isClosed) {
        output.addError(error, stackTrace);
      }
    } finally {
      _running = false;
      queue.close(discardPending: true);
      await source.stop();
      await producer;
      _pendingTurns = null;
      _runTask = null;
      await output.close();
    }
  }

  Future<TranscriptSegment?> _process(SpeechTurn turn) async {
    // Start both CPU workloads before awaiting either result.
    final transcriptFuture = transcriptionEngine.transcribe(turn);
    final speakerFuture = speakerEngine.attribute(turn);
    final transcript = await transcriptFuture;
    final speaker = await speakerFuture;

    if (transcript.displayText.trim().isEmpty) {
      return null;
    }

    return TranscriptSegment(
      eventId: turn.id,
      streamId: turn.streamId,
      speakerId: speaker.speakerId,
      speakerIndex: speaker.speakerIndex,
      rawText: transcript.rawText,
      displayText: transcript.displayText,
      locale: transcript.locale,
      startedAt: turn.startedAt,
      endedAt: turn.endedAt,
      model: transcript.model,
      isFinal: transcript.isFinal,
      transcriptConfidence: transcript.confidence,
      speakerConfidence: speaker.confidence,
    );
  }

  @override
  Future<void> stop() async {
    _requestStop();
    await source.stop();
    await _runTask;
  }

  void _requestStop() {
    _running = false;
    _pendingTurns?.close(discardPending: true);
  }

  Future<void> _cancelFromListener() async {
    _requestStop();
    await source.stop();
  }

  @override
  Future<void> close() => _closeTask ??= _close();

  Future<void> _close() async {
    _closed = true;
    await stop();
    await source.close();
    await transcriptionEngine.close();
    await speakerEngine.close();
  }
}

class _BoundedSpeechTurnQueue {
  _BoundedSpeechTurnQueue({required this.capacity});

  final int capacity;
  final ListQueue<SpeechTurn> _items = ListQueue<SpeechTurn>();
  Completer<SpeechTurn?>? _waitingConsumer;
  bool _closed = false;

  /// Returns true when adding this turn dropped the oldest pending turn.
  bool add(SpeechTurn turn) {
    if (_closed) {
      return false;
    }
    final consumer = _waitingConsumer;
    if (consumer != null) {
      _waitingConsumer = null;
      consumer.complete(turn);
      return false;
    }

    final dropped = _items.length == capacity;
    if (dropped) {
      _items.removeFirst();
    }
    _items.addLast(turn);
    return dropped;
  }

  Future<SpeechTurn?> take() {
    if (_items.isNotEmpty) {
      return Future<SpeechTurn?>.value(_items.removeFirst());
    }
    if (_closed) {
      return Future<SpeechTurn?>.value();
    }
    if (_waitingConsumer != null) {
      throw StateError('The speech turn queue supports one consumer.');
    }
    final consumer = Completer<SpeechTurn?>();
    _waitingConsumer = consumer;
    return consumer.future;
  }

  void close({bool discardPending = false}) {
    _closed = true;
    if (discardPending) {
      _items.clear();
    }
    if (_items.isEmpty) {
      final consumer = _waitingConsumer;
      _waitingConsumer = null;
      consumer?.complete();
    }
  }
}
