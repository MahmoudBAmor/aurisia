import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../../core/infrastructure/isolate_rpc_client.dart';
import '../../../../core/infrastructure/transferable_float32.dart';
import '../../domain/ports/speaker_attribution_engine.dart';
import '../../domain/speaker_attribution.dart';
import '../../domain/speech_turn.dart';
import '../speaker/online_speaker_clusterer.dart';

const bool _speakerDiagnosticsEnabled = bool.fromEnvironment(
  'AURISIA_ASR_DIAGNOSTICS',
);

class SherpaSpeakerAttributionEngine implements SpeakerAttributionEngine {
  SherpaSpeakerAttributionEngine._({
    required this._worker,
    required this._clusterer,
    required this.minimumEmbeddingDuration,
  });

  final IsolateRpcClient _worker;
  final OnlineSpeakerClusterer _clusterer;
  final Duration minimumEmbeddingDuration;

  static Future<SherpaSpeakerAttributionEngine> create({
    required String modelPath,
    int numberOfThreads = 1,
    double similarityThreshold = 0.5,
    double pendingSpeakerSimilarityThreshold = 0.7,
    double speakerSwitchMargin = 0.08,
    int maximumSpeakers = 6,
    int newSpeakerConfirmationCount = 3,
    Duration minimumEmbeddingDuration = const Duration(seconds: 1),
  }) async {
    final worker = await IsolateRpcClient.spawn(
      entrypoint: _speakerEmbeddingWorkerMain,
      configuration: <String, Object?>{
        'modelPath': modelPath,
        'numberOfThreads': numberOfThreads,
      },
    );
    return SherpaSpeakerAttributionEngine._(
      worker: worker,
      clusterer: OnlineSpeakerClusterer(
        similarityThreshold: similarityThreshold,
        pendingSpeakerSimilarityThreshold: pendingSpeakerSimilarityThreshold,
        speakerSwitchMargin: speakerSwitchMargin,
        maximumSpeakers: maximumSpeakers,
        newSpeakerConfirmationCount: newSpeakerConfirmationCount,
      ),
      minimumEmbeddingDuration: minimumEmbeddingDuration,
    );
  }

  @override
  Future<SpeakerAttribution> attribute(SpeechTurn turn) async {
    final sampleDuration = Duration(
      microseconds:
          (turn.samples.length *
                  Duration.microsecondsPerSecond /
                  turn.sampleRateHz)
              .round(),
    );
    if (sampleDuration < minimumEmbeddingDuration) {
      developer.log(
        'speaker=unchanged reason=short_turn '
        'audio_ms=${sampleDuration.inMilliseconds}',
        name: 'aurisia.speaker',
      );
      final attribution = _clusterer.reuseLastSpeaker();
      _emitSpeakerDiagnostic(
        turn: turn,
        attribution: attribution,
        reason: 'shortTurn',
      );
      return attribution;
    }
    final response = await _worker.request(
      'embed',
      payload: <String, Object?>{
        'samples': float32ToTransferable(turn.samples),
        'sampleRateHz': turn.sampleRateHz,
      },
    );
    final embedding = transferableToFloat32(
      response['embedding']! as TransferableTypedData,
    );
    final previousSpeakerCount = _clusterer.speakerCount;
    final decision = _clusterer.attributeWithDecision(embedding);
    final attribution = decision.attribution;
    developer.log(
      'speaker=${attribution.speakerIndex} '
      'similarity=${attribution.confidence?.toStringAsFixed(3) ?? 'unknown'} '
      'speaker_count=${_clusterer.speakerCount} '
      'new_speaker=${_clusterer.speakerCount > previousSpeakerCount} '
      'reason=${decision.reason.name}',
      name: 'aurisia.speaker',
    );
    _emitSpeakerDiagnostic(
      turn: turn,
      attribution: attribution,
      reason: decision.reason.name,
      bestSimilarity: decision.bestSimilarity,
      selectedSimilarity: decision.selectedSimilarity,
      createdSpeaker: decision.createdSpeaker,
    );
    return attribution;
  }

  void _emitSpeakerDiagnostic({
    required SpeechTurn turn,
    required SpeakerAttribution attribution,
    required String reason,
    double? bestSimilarity,
    double? selectedSimilarity,
    bool createdSpeaker = false,
  }) {
    if (!_speakerDiagnosticsEnabled) {
      return;
    }
    final audioMilliseconds =
        turn.samples.length * 1000 ~/ (turn.sampleRateHz * turn.channels);
    final payload = jsonEncode(<String, Object?>{
      'turn_id': turn.id,
      'audio_ms': audioMilliseconds,
      'speaker': attribution.speakerIndex,
      'speaker_count': _clusterer.speakerCount,
      'reason': reason,
      'best_similarity': bestSimilarity,
      'selected_similarity': selectedSimilarity,
      'created_speaker': createdSpeaker,
    });
    // Diagnostic builds record decision scores, never audio or embeddings.
    // ignore: avoid_print
    print('AURISIA_SPEAKER_DIAGNOSTIC $payload');
  }

  @override
  Future<void> reset() async {
    _clusterer.reset();
  }

  @override
  Future<void> close() => _worker.close();
}

Future<void> _speakerEmbeddingWorkerMain(List<Object?> bootstrap) async {
  final handshake = bootstrap[0]! as SendPort;
  final configuration = Map<String, Object?>.from(bootstrap[1]! as Map);
  sherpa.SpeakerEmbeddingExtractor? extractor;
  try {
    await sherpa.initBindingsAsync();
    extractor = sherpa.SpeakerEmbeddingExtractor(
      config: sherpa.SpeakerEmbeddingExtractorConfig(
        model: configuration['modelPath']! as String,
        numThreads: configuration['numberOfThreads']! as int,
        provider: 'cpu',
        debug: false,
      ),
    );
  } catch (error, stackTrace) {
    handshake.send(<String, Object?>{
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
    return;
  }

  final commands = ReceivePort();
  handshake.send(commands.sendPort);
  await for (final raw in commands) {
    final request = Map<String, Object?>.from(raw as Map);
    final replyTo = request['replyTo']! as SendPort;
    try {
      if (request['method'] == 'close') {
        extractor.free();
        replyTo.send(<String, Object?>{'ok': true});
        commands.close();
        break;
      }
      if (request['method'] != 'embed') {
        throw ArgumentError.value(request['method'], 'method');
      }

      final samples = transferableToFloat32(
        request['samples']! as TransferableTypedData,
      );
      final sampleRateHz = request['sampleRateHz']! as int;
      final stream = extractor.createStream();
      try {
        stream.acceptWaveform(samples: samples, sampleRate: sampleRateHz);
        stream.inputFinished();
        if (!extractor.isReady(stream)) {
          throw StateError(
            'The speech turn is too short for speaker attribution.',
          );
        }
        final embedding = extractor.compute(stream);
        replyTo.send(<String, Object?>{
          'embedding': float32ToTransferable(embedding),
        });
      } finally {
        stream.free();
      }
    } catch (error, stackTrace) {
      replyTo.send(<String, Object?>{
        'error': error.toString(),
        'stackTrace': stackTrace.toString(),
      });
    }
  }
}
