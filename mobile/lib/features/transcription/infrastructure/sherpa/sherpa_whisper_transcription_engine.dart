import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../../core/infrastructure/isolate_rpc_client.dart';
import '../../../../core/infrastructure/transferable_float32.dart';
import '../../domain/model_descriptor.dart';
import '../../domain/ports/transcription_engine.dart';
import '../../domain/speech_turn.dart';
import '../../domain/transcript_hypothesis.dart';

/// Turn-based multilingual Whisper adapter used to refine streaming output.
///
/// It is deliberately independent from Vosk: the streaming engine can be
/// replaced without changing this final recognizer, and vice versa.
class SherpaWhisperTranscriptionEngine implements TranscriptionEngine {
  SherpaWhisperTranscriptionEngine._({
    required this._worker,
    required this.model,
    required this.locale,
  });

  final IsolateRpcClient _worker;
  final ModelDescriptor model;
  final String locale;

  static Future<SherpaWhisperTranscriptionEngine> create({
    required String encoderPath,
    required String decoderPath,
    required String tokensPath,
    required ModelDescriptor model,
    String locale = 'ar',
    int numberOfThreads = 2,
  }) async {
    if (encoderPath.trim().isEmpty ||
        decoderPath.trim().isEmpty ||
        tokensPath.trim().isEmpty) {
      throw ArgumentError('Whisper model paths must not be empty.');
    }
    if (locale.trim().isEmpty) {
      throw ArgumentError.value(locale, 'locale');
    }
    final worker = await IsolateRpcClient.spawn(
      entrypoint: _whisperAsrWorkerMain,
      configuration: <String, Object?>{
        'encoderPath': encoderPath,
        'decoderPath': decoderPath,
        'tokensPath': tokensPath,
        'locale': locale,
        'numberOfThreads': numberOfThreads,
      },
    );
    return SherpaWhisperTranscriptionEngine._(
      worker: worker,
      model: model,
      locale: locale,
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
      locale: locale,
      model: model,
    );
  }

  @override
  Future<void> close() => _worker.close();
}

Future<void> _whisperAsrWorkerMain(List<Object?> bootstrap) async {
  final handshake = bootstrap[0]! as SendPort;
  final configuration = Map<String, Object?>.from(bootstrap[1]! as Map);
  sherpa.OfflineRecognizer? recognizer;
  try {
    await sherpa.initBindingsAsync();
    final whisper = sherpa.OfflineWhisperModelConfig(
      encoder: configuration['encoderPath']! as String,
      decoder: configuration['decoderPath']! as String,
      language: configuration['locale']! as String,
      task: 'transcribe',
    );
    final modelConfig = sherpa.OfflineModelConfig(
      whisper: whisper,
      tokens: configuration['tokensPath']! as String,
      numThreads: configuration['numberOfThreads']! as int,
      provider: 'cpu',
      modelType: 'whisper',
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
