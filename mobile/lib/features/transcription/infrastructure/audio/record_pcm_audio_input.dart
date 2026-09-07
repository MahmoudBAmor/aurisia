import 'dart:typed_data';

import 'package:record/record.dart';

import '../../domain/pcm_audio_frame.dart';
import '../../domain/ports/pcm_audio_input.dart';
import 'pcm_conversion.dart';

class MicrophonePermissionDeniedException implements Exception {
  const MicrophonePermissionDeniedException();

  @override
  String toString() => 'Microphone permission was denied.';
}

class UnsupportedMicrophoneFormatException implements Exception {
  const UnsupportedMicrophoneFormatException(this.message);

  final String message;

  @override
  String toString() => message;
}

class RecordPcmAudioInput implements PcmAudioInput {
  RecordPcmAudioInput({
    AudioRecorder? recorder,
    this.sampleRateHz = 16000,
    this.channels = 1,
  }) : _recorder = recorder ?? AudioRecorder();

  final AudioRecorder _recorder;
  final int sampleRateHz;
  final int channels;
  bool _running = false;
  RecordConfig? _effectiveConfig;
  Future<void>? _stopTask;

  @override
  Stream<PcmAudioFrame> start() async* {
    if (_running) {
      throw StateError('Microphone capture is already running.');
    }
    if (!await _recorder.hasPermission()) {
      throw const MicrophonePermissionDeniedException();
    }
    if (!await _recorder.isEncoderSupported(AudioEncoder.pcm16bits)) {
      throw const UnsupportedMicrophoneFormatException(
        'The device does not support streaming 16-bit PCM.',
      );
    }

    _running = true;
    _effectiveConfig = null;
    await _recorder.setOnConfigChanged((config) {
      _effectiveConfig = config;
    });

    const bytesPerSample = 2;
    final requestedConfig = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: sampleRateHz,
      numChannels: channels,
      autoGain: false,
      echoCancel: false,
      noiseSuppress: false,
      streamBufferSize: 1600 * bytesPerSample,
    );
    final byteStream = await _recorder.startStream(requestedConfig);
    final streamId = 'mobile-${DateTime.now().microsecondsSinceEpoch}';
    var sequence = 0;
    Uint8List carry = Uint8List(0);

    try {
      await for (final chunk in byteStream) {
        final effective = _effectiveConfig;
        if (effective != null &&
            (effective.sampleRate != sampleRateHz ||
                effective.numChannels != channels)) {
          throw UnsupportedMicrophoneFormatException(
            'Requested ${sampleRateHz}Hz/${channels}ch but the device supplied '
            '${effective.sampleRate}Hz/${effective.numChannels}ch.',
          );
        }

        final combined = carry.isEmpty
            ? chunk
            : Uint8List.fromList(<int>[...carry, ...chunk]);
        final evenLength = combined.length - (combined.length % bytesPerSample);
        if (evenLength == 0) {
          carry = combined;
          continue;
        }
        carry = evenLength == combined.length
            ? Uint8List(0)
            : Uint8List.sublistView(combined, evenLength);
        final samples = pcm16LeBytesToFloat32(
          Uint8List.sublistView(combined, 0, evenLength),
        );
        yield PcmAudioFrame(
          streamId: streamId,
          sequence: sequence++,
          capturedAt: DateTime.now(),
          sampleRateHz: sampleRateHz,
          channels: channels,
          samples: samples,
        );
      }
    } finally {
      _running = false;
      await _recorder.setOnConfigChanged(null);
    }
  }

  @override
  Future<void> stop() {
    final activeStop = _stopTask;
    if (activeStop != null) {
      return activeStop;
    }
    if (!_running) {
      return Future<void>.value();
    }

    final task = _stopRecorder();
    _stopTask = task;
    return task.whenComplete(() {
      _stopTask = null;
    });
  }

  Future<void> _stopRecorder() async {
    try {
      await _recorder.stop();
    } finally {
      _running = false;
    }
  }

  @override
  Future<void> close() async {
    await stop();
    await _recorder.dispose();
  }
}
