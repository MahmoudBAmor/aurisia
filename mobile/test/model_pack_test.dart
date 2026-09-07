import 'package:aurisia_mobile/core/model_packs/bundled_model_pack.dart';
import 'package:aurisia_mobile/core/model_packs/model_pack_materializer.dart';
import 'package:aurisia_mobile/features/transcription/application/live_transcription_composition.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults to the Android Tunisian model pack contract', () async {
    final pack = await BundledModelPackRepository().load();

    expect(pack.packId, 'aurisia-mobile-aeb-TN-vosk-full');
    expect(pack.locale, 'aeb-TN');
    expect(
      pack.artifacts.map((artifact) => artifact.role),
      containsAll(<String>{'asr_vosk_model', 'vad_model', 'speaker_model'}),
    );
  });

  test('loads the full Tunisian Vosk pack contract', () async {
    final pack = await BundledModelPackRepository().load(
      assetRoot: 'assets/model_packs/aeb-TN-vosk-full',
    );

    expect(pack.packId, 'aurisia-mobile-aeb-TN-vosk-full');
    expect(pack.locale, 'aeb-TN');
    expect(pack.bundledSizeBytes, 583722937);
    expect(pack.installedSizeBytes, 1501505144);
    final vosk = pack.artifacts.singleWhere(
      (artifact) => artifact.role == 'asr_vosk_model',
    );
    expect(vosk.kind, ModelArtifactKind.zipDirectory);
    expect(vosk.outputPath, 'vosk-model');
  });

  test('loads the formal Arabic streaming pack', () async {
    final pack = await BundledModelPackRepository().load(
      assetRoot: 'assets/model_packs/ar-MGB2-vosk',
    );

    expect(pack.packId, 'aurisia-mobile-ar-MGB2-vosk');
    expect(pack.locale, 'ar');
    expect(pack.bundledSizeBytes, 375162895);
    expect(pack.installedSizeBytes, 740116960);
    expect(
      pack.artifacts.map((artifact) => artifact.role),
      containsAll(<String>{'asr_vosk_model', 'vad_model', 'speaker_model'}),
    );
    final vosk = pack.artifacts.singleWhere(
      (artifact) => artifact.role == 'asr_vosk_model',
    );
    expect(vosk.archivePrefix, 'vosk-model-ar-mgb2-0.4');
    expect(vosk.outputSha256, hasLength(64));
  });

  test('loads the shared Qwen3 multilingual refinement pack', () async {
    final pack = await BundledModelPackRepository().load(
      assetRoot: 'assets/model_packs/qwen3-asr-0.6B-int8',
    );

    expect(pack.packId, 'aurisia-mobile-qwen3-asr-0.6B-int8');
    expect(pack.locale, 'mul');
    expect(pack.bundledSizeBytes, 987027033);
    expect(pack.installedSizeBytes, 987027033);
    expect(
      pack.artifacts.map((artifact) => artifact.role),
      containsAll(<String>{
        'asr_qwen3_conv_frontend',
        'asr_qwen3_encoder',
        'asr_qwen3_decoder',
        'asr_qwen3_tokenizer_merges',
        'asr_qwen3_tokenizer_config',
        'asr_qwen3_tokenizer_vocabulary',
        'model_license',
        'model_notice',
      }),
    );
    expect(
      pack.artifacts.where(
        (artifact) => artifact.path.startsWith('tokenizer/'),
      ),
      hasLength(3),
    );
  });

  test('rejects a traversal path in a model manifest', () {
    expect(
      () => ModelArtifact.fromJson(<String, Object?>{
        'role': 'asr_model',
        'path': '../model.onnx',
        'sha256': 'a' * 64,
        'size_bytes': 1,
      }),
      throwsFormatException,
    );
  });

  test('maps native artifact roles to replaceable live model paths', () {
    final paths = LiveModelPaths.fromRolePaths(const <String, String>{
      'asr_model': '/models/asr.onnx',
      'asr_tokens': '/models/tokens.txt',
      'vad_model': '/models/vad.onnx',
      'speaker_model': '/models/speaker.onnx',
    });

    final asr = paths.asr as OmnilingualAsrModelPaths;
    expect(asr.model, '/models/asr.onnx');
    expect(asr.tokens, '/models/tokens.txt');
    expect(paths.vadModel, '/models/vad.onnx');
    expect(paths.speakerEmbeddingModel, '/models/speaker.onnx');
  });

  test('selects Vosk when its replaceable model role is installed', () {
    final paths = LiveModelPaths.fromRolePaths(
      const <String, String>{
        'asr_vosk_model': '/models/android-model',
        'vad_model': '/models/vad.onnx',
        'speaker_model': '/models/speaker.onnx',
      },
      packId: 'formal-arabic',
      packVersion: '0.4',
      locale: 'ar',
    );

    final asr = paths.asr as VoskAsrModelPaths;
    expect(asr.modelDirectory, '/models/android-model');
    expect(asr.locale, 'ar');
    expect(asr.descriptor.id, 'formal-arabic');
    expect(asr.descriptor.version, '0.4');
  });

  test('adds an independent Whisper final recognizer when roles exist', () {
    final paths = LiveModelPaths.fromRolePaths(const <String, String>{
      'asr_vosk_model': '/models/android-model',
      'asr_whisper_encoder': '/models/whisper-encoder.onnx',
      'asr_whisper_decoder': '/models/whisper-decoder.onnx',
      'asr_whisper_tokens': '/models/whisper-tokens.txt',
      'vad_model': '/models/vad.onnx',
      'speaker_model': '/models/speaker.onnx',
    }, locale: 'ar');

    expect(paths.asr, isA<VoskAsrModelPaths>());
    final finalAsr = paths.finalAsr as WhisperAsrModelPaths;
    expect(finalAsr.encoder, '/models/whisper-encoder.onnx');
    expect(finalAsr.decoder, '/models/whisper-decoder.onnx');
    expect(finalAsr.tokens, '/models/whisper-tokens.txt');
    expect(finalAsr.locale, 'ar');
    expect(finalAsr.descriptor.id, 'whisper-small-int8-multilingual');
  });

  test('rejects an incomplete Whisper final recognizer contract', () {
    expect(
      () => LiveModelPaths.fromRolePaths(const <String, String>{
        'asr_vosk_model': '/models/android-model',
        'asr_whisper_encoder': '/models/whisper-encoder.onnx',
        'vad_model': '/models/vad.onnx',
        'speaker_model': '/models/speaker.onnx',
      }),
      throwsStateError,
    );
  });

  test('adds an independent Audar final recognizer when roles exist', () {
    final paths = LiveModelPaths.fromRolePaths(const <String, String>{
      'asr_vosk_model': '/models/android-model',
      'asr_audar_model': '/models/audar.gguf',
      'asr_audar_projector': '/models/mmproj.gguf',
      'vad_model': '/models/vad.onnx',
      'speaker_model': '/models/speaker.onnx',
    }, locale: 'ar');

    expect(paths.asr, isA<VoskAsrModelPaths>());
    final finalAsr = paths.finalAsr as AudarAsrModelPaths;
    expect(finalAsr.decoder, '/models/audar.gguf');
    expect(finalAsr.audioProjector, '/models/mmproj.gguf');
    expect(finalAsr.locale, 'ar');
  });

  test('rejects an incomplete Audar final recognizer contract', () {
    expect(
      () => LiveModelPaths.fromRolePaths(const <String, String>{
        'asr_vosk_model': '/models/android-model',
        'asr_audar_model': '/models/audar.gguf',
        'vad_model': '/models/vad.onnx',
        'speaker_model': '/models/speaker.onnx',
      }),
      throwsStateError,
    );
  });

  test('adds an independent Qwen3 final recognizer when roles exist', () {
    final paths = LiveModelPaths.fromRolePaths(const <String, String>{
      'asr_vosk_model': '/models/android-model',
      'asr_qwen3_conv_frontend': '/models/conv_frontend.onnx',
      'asr_qwen3_encoder': '/models/encoder.int8.onnx',
      'asr_qwen3_decoder': '/models/decoder.int8.onnx',
      'asr_qwen3_tokenizer_merges': '/models/tokenizer/merges.txt',
      'asr_qwen3_tokenizer_config': '/models/tokenizer/tokenizer_config.json',
      'asr_qwen3_tokenizer_vocabulary': '/models/tokenizer/vocab.json',
      'vad_model': '/models/vad.onnx',
      'speaker_model': '/models/speaker.onnx',
    }, locale: 'aeb-TN');

    expect(paths.asr, isA<VoskAsrModelPaths>());
    final finalAsr = paths.finalAsr as Qwen3AsrModelPaths;
    expect(finalAsr.convFrontend, '/models/conv_frontend.onnx');
    expect(finalAsr.encoder, '/models/encoder.int8.onnx');
    expect(finalAsr.decoder, '/models/decoder.int8.onnx');
    expect(finalAsr.tokenizer, '/models/tokenizer');
    expect(finalAsr.locale, 'aeb-TN');
  });

  test('rejects an incomplete Qwen3 final recognizer contract', () {
    expect(
      () => LiveModelPaths.fromRolePaths(const <String, String>{
        'asr_vosk_model': '/models/android-model',
        'asr_qwen3_encoder': '/models/encoder.int8.onnx',
        'vad_model': '/models/vad.onnx',
        'speaker_model': '/models/speaker.onnx',
      }),
      throwsStateError,
    );
  });

  test('sends a versioned pack contract to the native installer', () async {
    const channel = MethodChannel('com.aurisia/model_pack.test');
    MethodCall? received;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          received = call;
          return <String, String>{'asr_model': '/installed/model.onnx'};
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    const pack = BundledModelPack(
      packId: 'test-pack',
      version: '1.2.3',
      locale: 'aeb-TN',
      runtime: 'test',
      assetRoot: 'assets/model_packs/test',
      artifacts: <ModelArtifact>[
        ModelArtifact(
          role: 'asr_model',
          path: 'model.onnx',
          sha256: 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          sizeBytes: 42,
        ),
      ],
    );

    final paths = await const NativeModelPackMaterializer(channel)
        .materialize(pack);

    expect(paths['asr_model'], '/installed/model.onnx');
    expect(received?.method, 'materializeBundledPack');
    final arguments = Map<String, Object?>.from(received!.arguments as Map);
    expect(arguments['packId'], 'test-pack');
    expect(arguments['version'], '1.2.3');
    expect(arguments['assetRoot'], 'assets/model_packs/test');
  });
}
