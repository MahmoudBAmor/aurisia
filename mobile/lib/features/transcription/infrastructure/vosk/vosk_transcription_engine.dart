import 'dart:developer' as developer;

import 'package:flutter/services.dart';

import '../../domain/model_descriptor.dart';
import '../../domain/pcm_audio_frame.dart';
import '../../domain/ports/transcription_engine.dart';
import '../../domain/speech_turn.dart';
import '../../domain/transcript_candidate.dart';
import '../../domain/transcript_hypothesis.dart';
import '../audio/pcm_conversion.dart';

class VoskTranscriptionEngine implements StreamingTranscriptionEngine {
  VoskTranscriptionEngine._(this._channel, this._model, this._locale);

  static const String channelName = 'com.aurisia/asr/vosk';
  static const ModelDescriptor defaultModel = ModelDescriptor(
    id: 'linto-asr-ar-tn-android',
    version: '0.1+8ad50ec',
    runtime: 'vosk-android/0.3.75',
  );

  final MethodChannel _channel;
  final ModelDescriptor _model;
  final String _locale;
  bool _closed = false;
  bool _streaming = false;

  static Future<VoskTranscriptionEngine> create({
    required String modelDirectory,
    ModelDescriptor model = defaultModel,
    String locale = 'aeb-TN',
    int maximumAlternatives = 0,
    MethodChannel channel = const MethodChannel(channelName),
  }) async {
    if (modelDirectory.trim().isEmpty) {
      throw ArgumentError.value(modelDirectory, 'modelDirectory');
    }
    if (maximumAlternatives < 0 || maximumAlternatives > 10) {
      throw ArgumentError.value(maximumAlternatives, 'maximumAlternatives');
    }
    await channel.invokeMethod<void>('initialize', <String, Object>{
      'modelPath': modelDirectory,
      'maximumAlternatives': maximumAlternatives,
    });
    if (locale.trim().isEmpty) {
      throw ArgumentError.value(locale, 'locale');
    }
    return VoskTranscriptionEngine._(channel, model, locale);
  }

  @override
  Future<TranscriptHypothesis> transcribe(SpeechTurn turn) async {
    _ensureOpen();
    if (_streaming) {
      throw StateError(
        'Turn-based recognition cannot run during a live stream.',
      );
    }
    _validateFormat(turn.sampleRateHz, turn.channels);
    if (turn.samples.isEmpty) {
      return _emptyHypothesis();
    }

    final response = await _channel.invokeMapMethod<String, Object?>(
      'transcribe',
      <String, Object>{
        'pcm16': float32ToPcm16LeBytes(turn.samples),
        'sampleRateHz': turn.sampleRateHz,
      },
    );
    return _parseResponse(response, isFinal: true);
  }

  @override
  Future<void> startStream() async {
    _ensureOpen();
    if (_streaming) {
      throw StateError('The Vosk live stream is already active.');
    }
    await _channel.invokeMethod<void>('startStream');
    _streaming = true;
  }

  @override
  Future<TranscriptHypothesis> acceptFrame(PcmAudioFrame frame) async {
    _ensureStreaming();
    _validateFormat(frame.sampleRateHz, frame.channels);
    if (frame.samples.isEmpty) {
      return _emptyHypothesis(isFinal: false);
    }
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'acceptStreamFrame',
        <String, Object>{
          'pcm16': float32ToPcm16LeBytes(frame.samples),
          'sampleRateHz': frame.sampleRateHz,
        },
      );
      return _parseResponse(response, isFinal: false);
    } catch (_) {
      _streaming = false;
      rethrow;
    }
  }

  @override
  Future<TranscriptHypothesis> finishStream() async {
    _ensureStreaming();
    try {
      final response = await _channel.invokeMapMethod<String, Object?>(
        'finishStream',
      );
      return _parseResponse(response, isFinal: true);
    } finally {
      _streaming = false;
    }
  }

  TranscriptHypothesis _parseResponse(
    Map<String, Object?>? response, {
    required bool isFinal,
  }) {
    if (response == null || response['text'] is! String) {
      throw StateError('The native Vosk adapter returned an invalid result.');
    }
    final decoderCandidate = TranscriptCandidate(
      text: (response['text']! as String).trim(),
      confidence: _confidence(response['confidence']),
    );
    final alternatives = _parseAlternatives(response['alternatives']);
    if (isFinal) {
      _logFinalMetrics(response);
    }
    return TranscriptHypothesis(
      rawText: decoderCandidate.text,
      displayText: decoderCandidate.text,
      locale: _locale,
      model: _model,
      confidence: decoderCandidate.confidence,
      isFinal: isFinal,
      alternatives: alternatives,
    );
  }

  List<TranscriptCandidate> _parseAlternatives(Object? raw) {
    if (raw is! List<Object?>) {
      return const <TranscriptCandidate>[];
    }
    return raw
        .whereType<Map<Object?, Object?>>()
        .map(
          (alternative) => TranscriptCandidate(
            text: alternative['text']?.toString().trim() ?? '',
            confidence: _confidence(alternative['confidence']),
          ),
        )
        .where((alternative) => alternative.text.isNotEmpty)
        .toList(growable: false);
  }

  double? _confidence(Object? raw) =>
      raw is num ? raw.toDouble().clamp(0.0, 1.0).toDouble() : null;

  void _logFinalMetrics(Map<String, Object?> response) {
    final inferenceMilliseconds = response['inferenceMs'];
    final audioMilliseconds = response['audioMs'];
    if (inferenceMilliseconds is! num || audioMilliseconds is! num) {
      return;
    }
    final realTimeFactor = audioMilliseconds == 0
        ? 0.0
        : inferenceMilliseconds / audioMilliseconds;
    developer.log(
      'asr_inference_ms=${inferenceMilliseconds.round()} '
      'audio_ms=${audioMilliseconds.round()} '
      'rtf=${realTimeFactor.toStringAsFixed(2)}',
      name: 'aurisia.latency',
    );
  }

  TranscriptHypothesis _emptyHypothesis({bool isFinal = true}) {
    return TranscriptHypothesis(
      rawText: '',
      displayText: '',
      locale: _locale,
      model: _model,
      isFinal: isFinal,
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('The Vosk transcription engine is closed.');
    }
  }

  void _ensureStreaming() {
    _ensureOpen();
    if (!_streaming) {
      throw StateError('The Vosk live stream is not active.');
    }
  }

  void _validateFormat(int sampleRateHz, int channels) {
    if (sampleRateHz != 16000 || channels != 1) {
      throw ArgumentError(
        'Vosk requires 16000 Hz mono audio, got '
        '$sampleRateHz Hz/${channels}ch.',
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _streaming = false;
    await _channel.invokeMethod<void>('close');
  }
}
