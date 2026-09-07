import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import '../domain/pcm_audio_frame.dart';
import '../domain/ports/pcm_audio_input.dart';
import '../domain/ports/speaker_attribution_engine.dart';
import '../domain/ports/speech_segmenter.dart';
import '../domain/ports/transcription_engine.dart';
import '../domain/ports/transcription_session.dart';
import '../domain/speaker_attribution.dart';
import '../domain/speech_turn.dart';
import '../domain/transcript_hypothesis.dart';
import '../domain/transcript_segment.dart';
import 'streaming_hypothesis_policy.dart';

const bool _asrDiagnosticsEnabled = bool.fromEnvironment(
  'AURISIA_ASR_DIAGNOSTICS',
);

/// Coordinates live ASR, VAD, and speaker attribution without making one
/// adapter depend on another.
///
/// Partial text is published immediately with the most recent speaker. Once a
/// turn is complete, speaker attribution and optional final-ASR refinement
/// update the same event asynchronously, without blocking microphone capture.
class StreamingDefaultTranscriptionSession implements TranscriptionSession {
  StreamingDefaultTranscriptionSession({
    required this.audioInput,
    required this.segmenter,
    required this.transcriptionEngine,
    required this.speakerEngine,
    this.finalTranscriptionEngine,
    this.hypothesisPolicy = const StreamingHypothesisPolicy(),
    this.maximumRefinementAge = const Duration(seconds: 4),
  });

  final PcmAudioInput audioInput;
  final SpeechSegmenter segmenter;
  final StreamingTranscriptionEngine transcriptionEngine;
  final SpeakerAttributionEngine speakerEngine;
  final TranscriptionEngine? finalTranscriptionEngine;
  final StreamingHypothesisPolicy hypothesisPolicy;
  final Duration maximumRefinementAge;

  bool _running = false;
  bool _closed = false;
  bool _stopRequested = false;
  bool _cancelled = false;
  Future<void>? _runTask;
  Future<void>? _closeTask;
  Future<void> _speakerUpdates = Future<void>.value();
  Future<void>? _refinementWorker;
  _RefinementRequest? _pendingRefinement;
  SpeakerAttribution _lastSpeaker = const SpeakerAttribution(
    speakerId: 'session-speaker-0',
    speakerIndex: 0,
  );

  @override
  Stream<TranscriptSegment> start() {
    if (_closed) {
      throw StateError('The transcription session is closed.');
    }
    if (_running) {
      throw StateError('The transcription session is already running.');
    }
    _running = true;
    _stopRequested = false;
    _cancelled = false;
    _speakerUpdates = Future<void>.value();
    _refinementWorker = null;
    _pendingRefinement = null;
    _lastSpeaker = const SpeakerAttribution(
      speakerId: 'session-speaker-0',
      speakerIndex: 0,
    );

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
    var streamActive = false;
    var eventSequence = 0;
    DateTime? partialStartedAt;
    TranscriptHypothesis? lastPartial;
    final partialTracker = hypothesisPolicy.createTracker();

    try {
      await segmenter.reset();
      await speakerEngine.reset();
      await transcriptionEngine.startStream();
      streamActive = true;

      await for (final frame in audioInput.start()) {
        if (_cancelled) {
          break;
        }
        partialStartedAt ??= _frameStartedAt(frame);
        final turns = segmenter.acceptFrame(frame).toList(growable: false);
        if (turns.length > 1) {
          throw StateError(
            'Live VAD emitted multiple turns for one PCM frame.',
          );
        }

        final partial = await transcriptionEngine.acceptFrame(frame);
        partialTracker.observe(partial);
        if (turns.isEmpty) {
          if (partial.displayText.trim().isNotEmpty &&
              partial.displayText != lastPartial?.displayText) {
            lastPartial = partial;
            _publish(
              output,
              _segmentFromHypothesis(
                hypothesis: partial,
                eventId: _eventId(frame.streamId, eventSequence),
                streamId: frame.streamId,
                speaker: _lastSpeaker,
                startedAt: partialStartedAt,
                endedAt: frame.capturedAt,
                isFinal: false,
              ),
            );
          }
          continue;
        }

        final turn = turns.single;
        final finalHypothesis = await transcriptionEngine.finishStream();
        streamActive = false;
        final eventId = _eventId(turn.streamId, eventSequence);
        final selection = hypothesisPolicy.selectPrimaryFinal(
          finalHypothesis: finalHypothesis,
          stablePartial: partialTracker.stable,
          latestPartial: partialTracker.latest ?? lastPartial,
        );
        _logHypothesisSelection(eventId, 'streaming_final', selection);
        _publishFinalTurn(
          output: output,
          eventId: eventId,
          turn: turn,
          hypothesis: selection.hypothesis,
        );
        eventSequence += 1;
        lastPartial = null;
        partialStartedAt = null;
        partialTracker.reset();

        if (!_stopRequested && !_cancelled) {
          await transcriptionEngine.startStream();
          streamActive = true;
        }
      }

      if (!_cancelled) {
        final turns = segmenter.flush().toList(growable: false);
        if (turns.length > 1) {
          throw StateError('Live VAD emitted multiple turns while flushing.');
        }
        if (streamActive) {
          final finalHypothesis = await transcriptionEngine.finishStream();
          streamActive = false;
          if (turns.isNotEmpty) {
            final turn = turns.single;
            final eventId = _eventId(turn.streamId, eventSequence);
            final selection = hypothesisPolicy.selectPrimaryFinal(
              finalHypothesis: finalHypothesis,
              stablePartial: partialTracker.stable,
              latestPartial: partialTracker.latest ?? lastPartial,
            );
            _logHypothesisSelection(eventId, 'streaming_final', selection);
            _publishFinalTurn(
              output: output,
              eventId: eventId,
              turn: turn,
              hypothesis: selection.hypothesis,
            );
          }
        }
      }

      await _awaitBackgroundUpdates();
    } catch (error, stackTrace) {
      if (!_cancelled && !output.isClosed) {
        output.addError(error, stackTrace);
      }
    } finally {
      if (streamActive) {
        try {
          await transcriptionEngine.finishStream();
        } catch (error, stackTrace) {
          developer.log(
            'Could not finalize the abandoned ASR stream.',
            name: 'aurisia.streaming',
            error: error,
            stackTrace: stackTrace,
          );
        }
      }
      _running = false;
      _stopRequested = false;
      await audioInput.stop();
      await _awaitBackgroundUpdates();
      _runTask = null;
      if (!output.isClosed) {
        await output.close();
      }
    }
  }

  void _publishFinalTurn({
    required StreamController<TranscriptSegment> output,
    required String eventId,
    required SpeechTurn turn,
    required TranscriptHypothesis? hypothesis,
  }) {
    final asrLatency = _nonNegativeDifference(DateTime.now(), turn.endedAt);
    developer.log(
      'event=$eventId asr_final_latency_ms=${asrLatency.inMilliseconds}',
      name: 'aurisia.latency',
    );

    TranscriptSegment? provisional;
    if (hypothesis != null && hypothesis.displayText.trim().isNotEmpty) {
      provisional = _segmentFromHypothesis(
        hypothesis: hypothesis,
        eventId: eventId,
        streamId: turn.streamId,
        speaker: _lastSpeaker,
        startedAt: turn.startedAt,
        endedAt: turn.endedAt,
        isFinal: true,
      );
      _publish(output, provisional);
    }

    final speakerFuture = _scheduleSpeakerUpdate(
      output: output,
      eventId: eventId,
      turn: turn,
      hypothesis: hypothesis,
    );
    if (finalTranscriptionEngine != null) {
      _scheduleRefinement(
        _RefinementRequest(
          output: output,
          eventId: eventId,
          turn: turn,
          fallback: hypothesis,
          speaker: speakerFuture,
        ),
      );
    }
  }

  Future<SpeakerAttribution> _scheduleSpeakerUpdate({
    required StreamController<TranscriptSegment> output,
    required String eventId,
    required SpeechTurn turn,
    required TranscriptHypothesis? hypothesis,
  }) {
    final update = _speakerUpdates.then(
      (_) => _attributeSpeaker(eventId, turn),
    );
    _speakerUpdates = update.then((speaker) {
      _lastSpeaker = speaker;
      if (hypothesis != null && hypothesis.displayText.trim().isNotEmpty) {
        _publish(
          output,
          _segmentFromHypothesis(
            hypothesis: hypothesis,
            eventId: eventId,
            streamId: turn.streamId,
            speaker: speaker,
            startedAt: turn.startedAt,
            endedAt: turn.endedAt,
            isFinal: true,
          ),
        );
      }
    });
    return update;
  }

  void _scheduleRefinement(_RefinementRequest request) {
    if (_refinementWorker != null) {
      final replaced = _pendingRefinement;
      _pendingRefinement = request;
      if (replaced != null) {
        _logSkippedRefinement(replaced.eventId, 'superseded');
      }
      return;
    }

    late final Future<void> worker;
    worker = _runRefinementWorker(request).whenComplete(() {
      if (identical(_refinementWorker, worker)) {
        _refinementWorker = null;
      }
    });
    _refinementWorker = worker;
  }

  Future<void> _runRefinementWorker(_RefinementRequest first) async {
    _RefinementRequest? request = first;
    while (request != null) {
      if (_refinementIsStale(request.turn)) {
        _logSkippedRefinement(request.eventId, 'stale_before_inference');
      } else {
        final refinedHypothesis = await _refineFinalTranscript(
          request.eventId,
          request.turn,
          request.fallback,
        );
        final speaker = await request.speaker;
        if (_refinementIsStale(request.turn)) {
          _logSkippedRefinement(request.eventId, 'stale_after_inference');
        } else if (refinedHypothesis != null &&
            refinedHypothesis.displayText.trim().isNotEmpty) {
          _publish(
            request.output,
            _segmentFromHypothesis(
              hypothesis: refinedHypothesis,
              eventId: request.eventId,
              streamId: request.turn.streamId,
              speaker: speaker,
              startedAt: request.turn.startedAt,
              endedAt: request.turn.endedAt,
              isFinal: true,
            ),
          );
        }
      }
      request = _pendingRefinement;
      _pendingRefinement = null;
    }
  }

  bool _refinementIsStale(SpeechTurn turn) {
    if (maximumRefinementAge == Duration.zero) {
      return false;
    }
    return _nonNegativeDifference(DateTime.now(), turn.endedAt) >
        maximumRefinementAge;
  }

  void _logSkippedRefinement(String eventId, String reason) {
    developer.log(
      'event=$eventId final_asr_skipped=$reason',
      name: 'aurisia.latency',
    );
  }

  Future<void> _awaitBackgroundUpdates() async {
    await _speakerUpdates;
    final worker = _refinementWorker;
    if (worker != null) {
      await worker;
    }
  }

  Future<SpeakerAttribution> _attributeSpeaker(
    String eventId,
    SpeechTurn turn,
  ) async {
    final stopwatch = Stopwatch()..start();
    try {
      final speaker = await speakerEngine.attribute(turn);
      stopwatch.stop();
      developer.log(
        'event=$eventId speaker_ms=${stopwatch.elapsedMilliseconds} '
        'speaker=${speaker.speakerIndex}',
        name: 'aurisia.latency',
      );
      return speaker;
    } catch (error, stackTrace) {
      developer.log(
        'Speaker attribution failed; keeping the previous speaker.',
        name: 'aurisia.speaker',
        error: error,
        stackTrace: stackTrace,
      );
      return _lastSpeaker;
    }
  }

  Future<TranscriptHypothesis?> _refineFinalTranscript(
    String eventId,
    SpeechTurn turn,
    TranscriptHypothesis? fallback,
  ) async {
    final engine = finalTranscriptionEngine;
    if (engine == null) {
      return fallback;
    }
    final stopwatch = Stopwatch()..start();
    try {
      final refined = await engine.transcribe(turn);
      stopwatch.stop();
      final selection = hypothesisPolicy.selectRefinement(
        baseline: fallback,
        refinement: refined,
      );
      _emitAsrDiagnostic(
        eventId: eventId,
        turn: turn,
        baseline: fallback,
        refinement: refined,
        selection: selection,
        finalAsrMilliseconds: stopwatch.elapsedMilliseconds,
      );
      _logHypothesisSelection(eventId, 'final_refinement', selection);
      developer.log(
        'event=$eventId final_asr_ms=${stopwatch.elapsedMilliseconds} '
        'model=${refined.model.id}',
        name: 'aurisia.latency',
      );
      return selection.hypothesis;
    } catch (error, stackTrace) {
      developer.log(
        'Final transcript refinement failed; keeping the streaming result.',
        name: 'aurisia.transcription',
        error: error,
        stackTrace: stackTrace,
      );
      return fallback;
    }
  }

  void _emitAsrDiagnostic({
    required String eventId,
    required SpeechTurn turn,
    required TranscriptHypothesis? baseline,
    required TranscriptHypothesis refinement,
    required HypothesisSelection selection,
    required int finalAsrMilliseconds,
  }) {
    if (!_asrDiagnosticsEnabled) {
      return;
    }
    final payload = jsonEncode(<String, Object?>{
      'event_id': eventId,
      'audio_ms': turn.endedAt.difference(turn.startedAt).inMilliseconds,
      'baseline_model': baseline?.model.id,
      'baseline': baseline?.displayText,
      'refinement_model': refinement.model.id,
      'refinement': refinement.displayText,
      'selected_model': selection.hypothesis?.model.id,
      'selected': selection.hypothesis?.displayText,
      'reason': selection.reason.name,
      'similarity': selection.similarity,
      'final_asr_ms': finalAsrMilliseconds,
      'completed_age_ms': _nonNegativeDifference(
        DateTime.now(),
        turn.endedAt,
      ).inMilliseconds,
    });
    // This branch is compiled out unless an explicit diagnostic build enables
    // it. Production builds never print transcript content.
    // ignore: avoid_print
    print('AURISIA_ASR_DIAGNOSTIC $payload');
  }

  void _logHypothesisSelection(
    String eventId,
    String phase,
    HypothesisSelection selection,
  ) {
    final similarity = selection.similarity;
    developer.log(
      'event=$eventId phase=$phase '
      'choice=${selection.reason.name} '
      'similarity=${similarity?.toStringAsFixed(3) ?? 'unknown'}',
      name: 'aurisia.transcription',
    );
  }

  TranscriptSegment _segmentFromHypothesis({
    required TranscriptHypothesis hypothesis,
    required String eventId,
    required String streamId,
    required SpeakerAttribution speaker,
    required DateTime startedAt,
    required DateTime endedAt,
    required bool isFinal,
  }) {
    return TranscriptSegment(
      eventId: eventId,
      streamId: streamId,
      speakerId: speaker.speakerId,
      speakerIndex: speaker.speakerIndex,
      rawText: hypothesis.rawText,
      displayText: hypothesis.displayText,
      locale: hypothesis.locale,
      startedAt: startedAt,
      endedAt: endedAt,
      model: hypothesis.model,
      isFinal: isFinal,
      transcriptConfidence: hypothesis.confidence,
      speakerConfidence: speaker.confidence,
    );
  }

  void _publish(
    StreamController<TranscriptSegment> output,
    TranscriptSegment segment,
  ) {
    if (!_cancelled && !output.isClosed) {
      output.add(segment);
    }
  }

  DateTime _frameStartedAt(PcmAudioFrame frame) {
    final duration = Duration(
      microseconds:
          (frame.samples.length *
                  Duration.microsecondsPerSecond /
                  frame.sampleRateHz)
              .round(),
    );
    return frame.capturedAt.subtract(duration);
  }

  Duration _nonNegativeDifference(DateTime later, DateTime earlier) {
    final difference = later.difference(earlier);
    return difference.isNegative ? Duration.zero : difference;
  }

  String _eventId(String streamId, int sequence) => '$streamId-live-$sequence';

  @override
  Future<void> stop() async {
    if (!_running) {
      return;
    }
    _stopRequested = true;
    await audioInput.stop();
    await _runTask;
  }

  Future<void> _cancelFromListener() async {
    _cancelled = true;
    _stopRequested = true;
    await audioInput.stop();
  }

  @override
  Future<void> close() => _closeTask ??= _close();

  Future<void> _close() async {
    _closed = true;
    await stop();
    await audioInput.close();
    await segmenter.close();
    await transcriptionEngine.close();
    final finalEngine = finalTranscriptionEngine;
    if (finalEngine != null && !identical(finalEngine, transcriptionEngine)) {
      await finalEngine.close();
    }
    await speakerEngine.close();
  }
}

class _RefinementRequest {
  const _RefinementRequest({
    required this.output,
    required this.eventId,
    required this.turn,
    required this.fallback,
    required this.speaker,
  });

  final StreamController<TranscriptSegment> output;
  final String eventId;
  final SpeechTurn turn;
  final TranscriptHypothesis? fallback;
  final Future<SpeakerAttribution> speaker;
}
