import 'dart:typed_data';

import 'package:aurisia_mobile/features/transcription/domain/pcm_audio_frame.dart';
import 'package:aurisia_mobile/features/transcription/domain/speech_turn.dart';
import 'package:aurisia_mobile/features/transcription/infrastructure/vosk/vosk_transcription_engine.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'initializes and transcribes through the replaceable native adapter',
    () async {
      const channel = MethodChannel('com.aurisia/asr/vosk.test');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            if (call.method == 'transcribe') {
              return <String, Object?>{
                'text': 'كيفاش حالك',
                'confidence': 0.84,
              };
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final engine = await VoskTranscriptionEngine.create(
        modelDirectory: '/models/android-model',
        channel: channel,
      );
      final startedAt = DateTime.utc(2026);
      final result = await engine.transcribe(
        SpeechTurn(
          id: 'turn-1',
          streamId: 'stream-1',
          startedAt: startedAt,
          endedAt: startedAt.add(const Duration(milliseconds: 20)),
          sampleRateHz: 16000,
          channels: 1,
          samples: Float32List.fromList([-1, 0, 1]),
        ),
      );
      await engine.close();

      expect(calls.map((call) => call.method), <String>[
        'initialize',
        'transcribe',
        'close',
      ]);
      final initialize = Map<String, Object?>.from(
        calls.first.arguments as Map,
      );
      expect(initialize['modelPath'], '/models/android-model');
      expect(initialize['maximumAlternatives'], 0);
      final transcribe = Map<String, Object?>.from(calls[1].arguments as Map);
      expect(transcribe['sampleRateHz'], 16000);
      expect(transcribe['pcm16'], isA<Uint8List>());
      expect((transcribe['pcm16']! as Uint8List).length, 6);
      expect(result.rawText, 'كيفاش حالك');
      expect(result.confidence, 0.84);
      expect(result.model.id, 'linto-asr-ar-tn-android');
    },
  );

  test(
    'retains native n-best candidates without replacing the decoder result',
    () async {
      const channel = MethodChannel('com.aurisia/asr/vosk.alternatives.test');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'transcribe') {
              return <String, Object?>{
                'text': 'جيب الدواء',
                'confidence': 0.47,
                'alternatives': <Object?>[
                  <String, Object?>{'text': 'جيب الدواء', 'confidence': 0.47},
                  <String, Object?>{'text': 'جيب بانادول', 'confidence': 0.44},
                ],
              };
            }
            return null;
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final engine = await VoskTranscriptionEngine.create(
        modelDirectory: '/models/android-model',
        maximumAlternatives: 3,
        channel: channel,
      );
      final now = DateTime.utc(2026);

      final result = await engine.transcribe(
        SpeechTurn(
          id: 'turn-1',
          streamId: 'stream-1',
          startedAt: now,
          endedAt: now,
          sampleRateHz: 16000,
          channels: 1,
          samples: Float32List(1),
        ),
      );

      expect(result.rawText, 'جيب الدواء');
      expect(result.confidence, 0.47);
      expect(result.alternatives, hasLength(2));
      expect(result.alternatives.first.text, 'جيب الدواء');
      await engine.close();
    },
  );

  test('rejects audio outside the Vosk input contract', () async {
    const channel = MethodChannel('com.aurisia/asr/vosk.invalid.test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final engine = await VoskTranscriptionEngine.create(
      modelDirectory: '/models/android-model',
      channel: channel,
    );
    final now = DateTime.utc(2026);

    await expectLater(
      engine.transcribe(
        SpeechTurn(
          id: 'turn-1',
          streamId: 'stream-1',
          startedAt: now,
          endedAt: now,
          sampleRateHz: 48000,
          channels: 1,
          samples: Float32List(1),
        ),
      ),
      throwsArgumentError,
    );
    await engine.close();
  });

  test(
    'streams partial and final hypotheses through the same adapter',
    () async {
      const channel = MethodChannel('com.aurisia/asr/vosk.streaming.test');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'acceptStreamFrame' => <String, Object?>{
                'text': 'السلام عليكم',
                'confidence': 0.72,
              },
              'finishStream' => <String, Object?>{
                'text': 'صباح الخير يا صديقي',
                'confidence': 0.88,
              },
              _ => null,
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final engine = await VoskTranscriptionEngine.create(
        modelDirectory: '/models/android-model',
        channel: channel,
      );

      await engine.startStream();
      final partial = await engine.acceptFrame(
        PcmAudioFrame(
          streamId: 'stream-1',
          sequence: 0,
          capturedAt: DateTime.utc(2026),
          sampleRateHz: 16000,
          channels: 1,
          samples: Float32List.fromList([0.1, -0.1]),
        ),
      );
      final finalResult = await engine.finishStream();
      await engine.close();

      expect(calls.map((call) => call.method), <String>[
        'initialize',
        'startStream',
        'acceptStreamFrame',
        'finishStream',
        'close',
      ]);
      expect(partial.displayText, 'السلام عليكم');
      expect(partial.isFinal, isFalse);
      expect(finalResult.displayText, 'صباح الخير يا صديقي');
      expect(finalResult.isFinal, isTrue);
    },
  );
}
