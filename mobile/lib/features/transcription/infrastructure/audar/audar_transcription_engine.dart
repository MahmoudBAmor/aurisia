import 'package:llama_cpp_dart/llama_cpp_dart.dart';

import '../../domain/model_descriptor.dart';
import '../../domain/ports/transcription_engine.dart';
import '../../domain/speech_turn.dart';
import '../../domain/transcript_hypothesis.dart';
import '../audio/wave_encoding.dart';
import 'audar_transcript_parser.dart';

/// CPU-only, turn-based adapter for the Arabic-first Audar ASR model.
///
/// Vosk remains the independent streaming recognizer. This adapter only
/// refines a completed turn and can be replaced without changing session,
/// VAD, speaker attribution, or presentation code.
class AudarTranscriptionEngine implements TranscriptionEngine {
  AudarTranscriptionEngine._({required this._engine, required this.locale});

  static const ModelDescriptor _model = ModelDescriptor(
    id: 'audar-asr-v1-flash-q8_0',
    version: '54274d3',
    runtime: 'llama-cpp-dart/0.9.0-dev.12+b10182',
  );
  static const String _systemPrompt = 'فرّغ الكلام العربي التالي.';
  static const int _maximumAudioSeconds = 30;

  final LlamaEngine _engine;
  final String locale;

  static Future<AudarTranscriptionEngine> create({
    required String decoderPath,
    required String audioProjectorPath,
    String locale = 'ar',
  }) async {
    if (decoderPath.trim().isEmpty || audioProjectorPath.trim().isEmpty) {
      throw ArgumentError('Audar model paths must not be empty.');
    }
    if (locale.trim().isEmpty) {
      throw ArgumentError.value(locale, 'locale');
    }

    final engine = await LlamaEngine.spawn(
      modelParams: ModelParams(path: decoderPath, gpuLayers: 0, useMmap: true),
      contextParams: ContextParams.mobile(
        nCtx: 4096,
        nBatch: 512,
        nUbatch: 256,
      ),
      multimodalParams: MultimodalParams(
        mmprojPath: audioProjectorPath,
        useGpu: false,
        nThreads: 4,
        warmup: true,
      ),
    );
    if (!engine.supportsAudio) {
      await engine.dispose();
      throw StateError(
        'The installed Audar projector does not advertise audio support.',
      );
    }
    return AudarTranscriptionEngine._(engine: engine, locale: locale);
  }

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    if (turn.channels != 1) {
      throw ArgumentError.value(
        turn.channels,
        'turn.channels',
        'Audar requires normalized mono audio.',
      );
    }
    if (turn.samples.length > turn.sampleRateHz * _maximumAudioSeconds) {
      throw ArgumentError(
        'Audar supports at most $_maximumAudioSeconds seconds per turn.',
      );
    }
    if (turn.samples.isEmpty) {
      return TranscriptHypothesis(
        rawText: '',
        displayText: '',
        locale: locale,
        model: _model,
      );
    }

    final wave = encodeMonoPcm16Wave(
      samples: turn.samples,
      sampleRateHz: turn.sampleRateHz,
    );
    final chat = await _engine.createChat();
    final raw = StringBuffer();
    try {
      chat
        ..addSystem(_systemPrompt)
        ..addUser(
          '',
          media: <LlamaMedia>[LlamaMedia.audioBytes(wave, id: turn.id)],
        );
      await for (final event in chat.generate(
        sampler: SamplerParams.greedyDefault,
        maxTokens: 256,
      )) {
        switch (event) {
          case TokenEvent():
            raw.write(event.text);
          case ShiftEvent():
            break;
          case DoneEvent():
            raw.write(event.trailingText);
        }
      }
    } finally {
      await chat.dispose();
    }

    final rawText = raw.toString().trim();
    return TranscriptHypothesis(
      rawText: rawText,
      displayText: parseAudarTranscript(rawText),
      locale: locale,
      model: _model,
    );
  }

  @override
  Future<void> close() => _engine.dispose();
}
