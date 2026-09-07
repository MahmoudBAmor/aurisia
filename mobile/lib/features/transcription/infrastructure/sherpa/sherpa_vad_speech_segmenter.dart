import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../../domain/pcm_audio_frame.dart';
import '../../domain/ports/speech_segmenter.dart';
import '../../domain/speech_turn.dart';
import 'sherpa_runtime.dart';

class SherpaVadSpeechSegmenter implements SpeechSegmenter {
  SherpaVadSpeechSegmenter._({
    required this._detector,
    required this.sampleRateHz,
  });

  final sherpa.VoiceActivityDetector _detector;
  final int sampleRateHz;
  DateTime? _streamEpoch;
  String? _streamId;

  static Future<SherpaVadSpeechSegmenter> create({
    required String modelPath,
    int sampleRateHz = 16000,
    double threshold = 0.5,
    double minSilenceSeconds = 0.35,
    double minSpeechSeconds = 0.25,
    double maxSpeechSeconds = 12,
  }) async {
    await SherpaRuntime.ensureInitialized();
    final config = sherpa.VadModelConfig(
      sileroVad: sherpa.SileroVadModelConfig(
        model: modelPath,
        threshold: threshold,
        minSilenceDuration: minSilenceSeconds,
        minSpeechDuration: minSpeechSeconds,
        maxSpeechDuration: maxSpeechSeconds,
      ),
      sampleRate: sampleRateHz,
      numThreads: 1,
      provider: 'cpu',
      debug: false,
    );
    return SherpaVadSpeechSegmenter._(
      detector: sherpa.VoiceActivityDetector(
        config: config,
        bufferSizeInSeconds: maxSpeechSeconds + 5,
      ),
      sampleRateHz: sampleRateHz,
    );
  }

  @override
  Iterable<SpeechTurn> acceptFrame(PcmAudioFrame frame) {
    _validateFormat(frame);
    _streamId ??= frame.streamId;
    _streamEpoch ??= frame.capturedAt.subtract(
      _samplesToDuration(frame.samples.length),
    );
    if (_streamId != frame.streamId) {
      throw StateError('The audio stream identifier changed during capture.');
    }

    _detector.acceptWaveform(frame.samples);
    return _drainSegments().toList(growable: false);
  }

  @override
  Iterable<SpeechTurn> flush() {
    _detector.flush();
    return _drainSegments().toList(growable: false);
  }

  Iterable<SpeechTurn> _drainSegments() sync* {
    while (!_detector.isEmpty()) {
      final segment = _detector.front();
      _detector.pop();
      if (segment.samples.isEmpty) {
        continue;
      }

      final streamId = _streamId;
      final epoch = _streamEpoch;
      if (streamId == null || epoch == null) {
        throw StateError(
          'VAD emitted speech before the stream was initialized.',
        );
      }
      final startSample = segment.start;
      final endSample = startSample + segment.samples.length;
      yield SpeechTurn(
        id: '$streamId-$startSample-$endSample',
        streamId: streamId,
        startedAt: epoch.add(_samplesToDuration(startSample)),
        endedAt: epoch.add(_samplesToDuration(endSample)),
        sampleRateHz: sampleRateHz,
        channels: 1,
        samples: segment.samples,
      );
    }
  }

  Duration _samplesToDuration(int sampleCount) {
    return Duration(
      microseconds:
          (sampleCount * Duration.microsecondsPerSecond / sampleRateHz).round(),
    );
  }

  void _validateFormat(PcmAudioFrame frame) {
    if (frame.sampleRateHz != sampleRateHz || frame.channels != 1) {
      throw ArgumentError(
        'VAD requires ${sampleRateHz}Hz mono audio, got '
        '${frame.sampleRateHz}Hz/${frame.channels}ch.',
      );
    }
  }

  @override
  Future<void> reset() async {
    _detector.reset();
    _streamEpoch = null;
    _streamId = null;
  }

  @override
  Future<void> close() async {
    _detector.free();
  }
}
