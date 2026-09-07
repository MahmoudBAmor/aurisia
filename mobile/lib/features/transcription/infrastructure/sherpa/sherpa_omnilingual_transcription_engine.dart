import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../../core/infrastructure/isolate_rpc_client.dart';
import '../../../../core/infrastructure/transferable_float32.dart';
import '../../domain/model_descriptor.dart';
import '../../domain/ports/transcription_engine.dart';
import '../../domain/speech_turn.dart';
import '../../domain/transcript_hypothesis.dart';

class SherpaOmnilingualTranscriptionEngine implements TranscriptionEngine {
  SherpaOmnilingualTranscriptionEngine._({
    required this._worker,
    required this.model,
  });

  final IsolateRpcClient _worker;
  final ModelDescriptor model;

  static Future<SherpaOmnilingualTranscriptionEngine> create({
    required String modelPath,
    required String tokensPath,
    int numberOfThreads = 2,
  }) async {
    final worker = await IsolateRpcClient.spawn(
      entrypoint: _omnilingualAsrWorkerMain,
      configuration: <String, Object?>{
        'modelPath': modelPath,
        'tokensPath': tokensPath,
        'numberOfThreads': numberOfThreads,
      },
    );
    return SherpaOmnilingualTranscriptionEngine._(
      worker: worker,
      model: const ModelDescriptor(
        id: 'omnilingual-asr-300m-ctc-int8-aeb',
        version: '2025-11-12',
        runtime: 'sherpa-onnx-1.13.6',
      ),
    );
  }

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    final response = await _worker.request(
      'transcribe',
      payload: <String, Object?>{
        'samples': float32ToTransferable(turn.samples),
        'sampleRateHz': turn.sampleRateHz,
      },
    );
    final text = response['text'].toString().trim();
    return TranscriptHypothesis(
      rawText: text,
      displayText: text,
      locale: 'aeb-TN',
      model: model,
    );
  }

  @override
  Future<void> close() => _worker.close();
}

Future<void> _omnilingualAsrWorkerMain(List<Object?> bootstrap) async {
  final handshake = bootstrap[0]! as SendPort;
  final configuration = Map<String, Object?>.from(bootstrap[1]! as Map);
  sherpa.OfflineRecognizer? recognizer;
  try {
    await sherpa.initBindingsAsync();
    final omnilingual = sherpa.OfflineOmnilingualAsrCtcModelConfig(
      model: configuration['modelPath']! as String,
    );
    final modelConfig = sherpa.OfflineModelConfig(
      omnilingual: omnilingual,
      tokens: configuration['tokensPath']! as String,
      numThreads: configuration['numberOfThreads']! as int,
      provider: 'cpu',
      debug: false,
    );
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(model: modelConfig),
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
        recognizer.free();
        replyTo.send(<String, Object?>{'ok': true});
        commands.close();
        break;
      }
      if (request['method'] != 'transcribe') {
        throw ArgumentError.value(request['method'], 'method');
      }

      final samples = transferableToFloat32(
        request['samples']! as TransferableTypedData,
      );
      final stream = recognizer.createStream();
      try {
        stream.acceptWaveform(
          samples: samples,
          sampleRate: request['sampleRateHz']! as int,
        );
        recognizer.decode(stream);
        final result = recognizer.getResult(stream);
        replyTo.send(<String, Object?>{'text': result.text});
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
