import 'dart:isolate';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../../../core/infrastructure/isolate_rpc_client.dart';
import '../../../../core/infrastructure/transferable_float32.dart';
import '../../domain/model_descriptor.dart';
import '../../domain/ports/transcription_engine.dart';
import '../../domain/speech_turn.dart';
import '../../domain/transcript_hypothesis.dart';

/// CPU-only, turn-based Qwen3-ASR adapter for multilingual final recognition.
///
/// The engine stays behind [TranscriptionEngine]: Vosk can continue providing
/// low-latency partials while this stronger model refines completed turns in a
/// worker isolate. A per-turn language hint prevents the generative decoder
/// from drifting to an unrelated language on short or ambiguous audio.
class SherpaQwen3TranscriptionEngine implements TranscriptionEngine {
  SherpaQwen3TranscriptionEngine._({
    required this._worker,
    required this.locale,
  });

  static const ModelDescriptor _model = ModelDescriptor(
    id: 'qwen3-asr-0.6b-int8',
    version: '2026-03-25',
    runtime: 'sherpa-onnx-1.13.6',
  );

  final IsolateRpcClient _worker;
  final String locale;

  static Future<SherpaQwen3TranscriptionEngine> create({
    required String convFrontendPath,
    required String encoderPath,
    required String decoderPath,
    required String tokenizerPath,
    required String locale,
    required String language,
    List<String> hotwords = const <String>[],
    int numberOfThreads = 3,
  }) async {
    final requiredPaths = <String>[
      convFrontendPath,
      encoderPath,
      decoderPath,
      tokenizerPath,
    ];
    if (requiredPaths.any((path) => path.trim().isEmpty)) {
      throw ArgumentError('Qwen3-ASR model paths must not be empty.');
    }
    if (locale.trim().isEmpty) {
      throw ArgumentError.value(locale, 'locale');
    }
    final normalizedLanguage = language.trim();
    if (normalizedLanguage.isEmpty) {
      throw ArgumentError.value(language, 'language');
    }
    if (numberOfThreads <= 0) {
      throw ArgumentError.value(numberOfThreads, 'numberOfThreads');
    }

    final normalizedHotwords = hotwords
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty && !word.contains(','))
        .toSet()
        .join(',');
    final worker = await IsolateRpcClient.spawn(
      entrypoint: _qwen3AsrWorkerMain,
      configuration: <String, Object?>{
        'convFrontendPath': convFrontendPath,
        'encoderPath': encoderPath,
        'decoderPath': decoderPath,
        'tokenizerPath': tokenizerPath,
        'language': normalizedLanguage,
        'hotwords': normalizedHotwords,
        'numberOfThreads': numberOfThreads,
      },
    );
    return SherpaQwen3TranscriptionEngine._(worker: worker, locale: locale);
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
      model: _model,
    );
  }

  @override
  Future<void> close() => _worker.close();
}

Future<void> _qwen3AsrWorkerMain(List<Object?> bootstrap) async {
  final handshake = bootstrap[0]! as SendPort;
  final configuration = Map<String, Object?>.from(bootstrap[1]! as Map);
  sherpa.OfflineRecognizer? recognizer;
  try {
    await sherpa.initBindingsAsync();
    final qwen3 = sherpa.OfflineQwen3AsrModelConfig(
      convFrontend: configuration['convFrontendPath']! as String,
      encoder: configuration['encoderPath']! as String,
      decoder: configuration['decoderPath']! as String,
      tokenizer: configuration['tokenizerPath']! as String,
      hotwords: configuration['hotwords']! as String,
      maxTotalLen: 512,
      maxNewTokens: 128,
      temperature: 1e-6,
      topP: 0.8,
      seed: 42,
    );
    recognizer = sherpa.OfflineRecognizer(
      sherpa.OfflineRecognizerConfig(
        feat: const sherpa.FeatureConfig(sampleRate: 16000, featureDim: 128),
        model: sherpa.OfflineModelConfig(
          qwen3Asr: qwen3,
          tokens: '',
          numThreads: configuration['numberOfThreads']! as int,
          provider: 'cpu',
          debug: false,
        ),
        decodingMethod: 'greedy_search',
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
      final sampleRateHz = request['sampleRateHz']! as int;
      if (sampleRateHz != 16000) {
        throw ArgumentError.value(
          sampleRateHz,
          'sampleRateHz',
          'Qwen3-ASR requires 16 kHz audio.',
        );
      }
      final stream = recognizer.createStream();
      try {
        stream.setOption(
          key: 'language',
          value: configuration['language']! as String,
        );
        stream.acceptWaveform(samples: samples, sampleRate: sampleRateHz);
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
