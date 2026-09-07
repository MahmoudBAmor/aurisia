import 'dart:io';

import '../domain/model_descriptor.dart';
import '../domain/ports/transcription_engine.dart';
import '../domain/ports/transcription_session.dart';
import '../infrastructure/audio/record_pcm_audio_input.dart';
import '../infrastructure/audio/sustained_phonation_compressor.dart';
import '../infrastructure/audio/trailing_silence_padder.dart';
import '../infrastructure/audar/audar_transcription_engine.dart';
import '../infrastructure/language/arabic_script_normalizer.dart';
import '../infrastructure/sherpa/sherpa_omnilingual_transcription_engine.dart';
import '../infrastructure/sherpa/sherpa_qwen3_transcription_engine.dart';
import '../infrastructure/sherpa/sherpa_speaker_attribution_engine.dart';
import '../infrastructure/sherpa/sherpa_vad_speech_segmenter.dart';
import '../infrastructure/sherpa/sherpa_whisper_transcription_engine.dart';
import '../infrastructure/vosk/vosk_transcription_engine.dart';
import 'default_transcription_session.dart';
import 'context_padding_speech_segmenter.dart';
import 'live_transcription_profile.dart';
import 'normalizing_transcription_engine.dart';
import 'preprocessing_transcription_engine.dart';
import 'segmented_speech_turn_source.dart';
import 'streaming_transcription_session.dart';

sealed class LiveAsrModelPaths {
  const LiveAsrModelPaths();
}

class VoskAsrModelPaths extends LiveAsrModelPaths {
  const VoskAsrModelPaths({
    required this.modelDirectory,
    required this.locale,
    required this.descriptor,
  });

  final String modelDirectory;
  final String locale;
  final ModelDescriptor descriptor;
}

class OmnilingualAsrModelPaths extends LiveAsrModelPaths {
  const OmnilingualAsrModelPaths({required this.model, required this.tokens});

  final String model;
  final String tokens;
}

class WhisperAsrModelPaths extends LiveAsrModelPaths {
  const WhisperAsrModelPaths({
    required this.encoder,
    required this.decoder,
    required this.tokens,
    required this.locale,
    required this.descriptor,
  });

  final String encoder;
  final String decoder;
  final String tokens;
  final String locale;
  final ModelDescriptor descriptor;
}

class AudarAsrModelPaths extends LiveAsrModelPaths {
  const AudarAsrModelPaths({
    required this.decoder,
    required this.audioProjector,
    required this.locale,
  });

  final String decoder;
  final String audioProjector;
  final String locale;
}

class Qwen3AsrModelPaths extends LiveAsrModelPaths {
  const Qwen3AsrModelPaths({
    required this.convFrontend,
    required this.encoder,
    required this.decoder,
    required this.tokenizer,
    required this.locale,
  });

  final String convFrontend;
  final String encoder;
  final String decoder;
  final String tokenizer;
  final String locale;
}

class LiveModelPaths {
  const LiveModelPaths({
    required this.asr,
    required this.vadModel,
    required this.speakerEmbeddingModel,
    this.finalAsr,
  });

  final LiveAsrModelPaths asr;
  final LiveAsrModelPaths? finalAsr;
  final String vadModel;
  final String speakerEmbeddingModel;

  factory LiveModelPaths.fromRolePaths(
    Map<String, String> paths, {
    String packId = 'aurisia-mobile-aeb-TN-vosk-full',
    String packVersion = '1.0.0',
    String locale = 'aeb-TN',
    String runtime = 'vosk-android/0.3.75',
    String finalPackId = 'whisper-small-int8-multilingual',
    String finalPackVersion = '8f3c18b',
    String finalRuntime = 'sherpa-onnx-1.13.6',
  }) {
    String requiredPath(String role) {
      final path = paths[role];
      if (path == null || path.isEmpty) {
        throw StateError('Model pack is missing the "$role" artifact.');
      }
      return path;
    }

    final LiveAsrModelPaths asr;
    final voskModelDirectory = paths['asr_vosk_model'];
    if (voskModelDirectory != null && voskModelDirectory.isNotEmpty) {
      asr = VoskAsrModelPaths(
        modelDirectory: voskModelDirectory,
        locale: locale,
        descriptor: ModelDescriptor(
          id: packId,
          version: packVersion,
          runtime: runtime,
        ),
      );
    } else {
      asr = OmnilingualAsrModelPaths(
        model: requiredPath('asr_model'),
        tokens: requiredPath('asr_tokens'),
      );
    }

    final whisperEncoder = paths['asr_whisper_encoder'];
    final whisperDecoder = paths['asr_whisper_decoder'];
    final whisperTokens = paths['asr_whisper_tokens'];
    final hasAnyWhisperRole =
        whisperEncoder != null ||
        whisperDecoder != null ||
        whisperTokens != null;
    final audarDecoder = paths['asr_audar_model'];
    final audarProjector = paths['asr_audar_projector'];
    final hasAnyAudarRole = audarDecoder != null || audarProjector != null;
    final qwenConvFrontend = paths['asr_qwen3_conv_frontend'];
    final qwenEncoder = paths['asr_qwen3_encoder'];
    final qwenDecoder = paths['asr_qwen3_decoder'];
    final qwenTokenizerMerges = paths['asr_qwen3_tokenizer_merges'];
    final qwenTokenizerConfig = paths['asr_qwen3_tokenizer_config'];
    final qwenTokenizerVocabulary = paths['asr_qwen3_tokenizer_vocabulary'];
    final hasAnyQwenRole =
        qwenConvFrontend != null ||
        qwenEncoder != null ||
        qwenDecoder != null ||
        qwenTokenizerMerges != null ||
        qwenTokenizerConfig != null ||
        qwenTokenizerVocabulary != null;
    if (<bool>[
          hasAnyWhisperRole,
          hasAnyAudarRole,
          hasAnyQwenRole,
        ].where((configured) => configured).length >
        1) {
      throw StateError(
        'A model pack must configure exactly one final ASR recognizer.',
      );
    }

    final LiveAsrModelPaths? finalAsr;
    if (hasAnyWhisperRole) {
      if (whisperEncoder == null ||
          whisperEncoder.isEmpty ||
          whisperDecoder == null ||
          whisperDecoder.isEmpty ||
          whisperTokens == null ||
          whisperTokens.isEmpty) {
        throw StateError(
          'Whisper refinement requires encoder, decoder, and tokens.',
        );
      }
      finalAsr = WhisperAsrModelPaths(
        encoder: whisperEncoder,
        decoder: whisperDecoder,
        tokens: whisperTokens,
        locale: locale,
        descriptor: ModelDescriptor(
          id: finalPackId,
          version: finalPackVersion,
          runtime: finalRuntime,
        ),
      );
    } else if (hasAnyAudarRole) {
      if (audarDecoder == null ||
          audarDecoder.isEmpty ||
          audarProjector == null ||
          audarProjector.isEmpty) {
        throw StateError(
          'Audar refinement requires decoder and audio projector artifacts.',
        );
      }
      finalAsr = AudarAsrModelPaths(
        decoder: audarDecoder,
        audioProjector: audarProjector,
        locale: locale,
      );
    } else if (hasAnyQwenRole) {
      if (qwenConvFrontend == null ||
          qwenConvFrontend.isEmpty ||
          qwenEncoder == null ||
          qwenEncoder.isEmpty ||
          qwenDecoder == null ||
          qwenDecoder.isEmpty ||
          qwenTokenizerMerges == null ||
          qwenTokenizerMerges.isEmpty ||
          qwenTokenizerConfig == null ||
          qwenTokenizerConfig.isEmpty ||
          qwenTokenizerVocabulary == null ||
          qwenTokenizerVocabulary.isEmpty) {
        throw StateError(
          'Qwen3 refinement requires frontend, encoder, decoder, and '
          'tokenizer artifacts.',
        );
      }
      final tokenizerDirectory = File(qwenTokenizerConfig).parent.path;
      if (File(qwenTokenizerMerges).parent.path != tokenizerDirectory ||
          File(qwenTokenizerVocabulary).parent.path != tokenizerDirectory) {
        throw StateError(
          'Qwen3 tokenizer artifacts must share one installed directory.',
        );
      }
      finalAsr = Qwen3AsrModelPaths(
        convFrontend: qwenConvFrontend,
        encoder: qwenEncoder,
        decoder: qwenDecoder,
        tokenizer: tokenizerDirectory,
        locale: locale,
      );
    } else {
      finalAsr = null;
    }

    return LiveModelPaths(
      asr: asr,
      finalAsr: finalAsr,
      vadModel: requiredPath('vad_model'),
      speakerEmbeddingModel: requiredPath('speaker_model'),
    );
  }
}

Future<TranscriptionSession> createLiveTranscriptionSession({
  required LiveModelPaths models,
  LiveTranscriptionProfile profile =
      LiveTranscriptionProfile.tunisianConversation,
}) async {
  final audio = RecordPcmAudioInput();
  final rawVad = await SherpaVadSpeechSegmenter.create(
    modelPath: models.vadModel,
    // Streaming partials keep the UI responsive while the profile controls
    // how much linguistic and vocal context constitutes one final turn.
    minSilenceSeconds: profile.minimumSilenceSeconds,
    maxSpeechSeconds: profile.maximumSpeechSeconds,
  );
  final vad = ContextPaddingSpeechSegmenter(
    segmenter: rawVad,
    leadingPadding: profile.leadingSpeechPadding,
    trailingPadding: profile.trailingSpeechPadding,
    historyDuration: Duration(
      milliseconds: ((profile.maximumSpeechSeconds + 5) * 1000).round(),
    ),
  );

  try {
    final normalizer = await ArabicScriptNormalizer.load(
      assetPath: profile.displayLexiconAssetPath,
    );
    final rawTranscription = await _createTranscriptionEngine(models.asr);
    TranscriptionEngine? rawFinalTranscription;
    try {
      final finalAsr = models.finalAsr;
      if (finalAsr != null) {
        rawFinalTranscription = await _createTranscriptionEngine(
          finalAsr,
          languageHint: profile.finalAsrLanguageHint,
        );
        if (profile.normalizeSustainedPhonation &&
            finalAsr is! Qwen3AsrModelPaths) {
          rawFinalTranscription = PreprocessingTranscriptionEngine(
            engine: rawFinalTranscription,
            preprocessor: SustainedPhonationCompressor(),
          );
        }
        if (profile.finalAsrTrailingSilence.inMicroseconds > 0) {
          rawFinalTranscription = PreprocessingTranscriptionEngine(
            engine: rawFinalTranscription,
            preprocessor: TrailingSilencePadder(
              duration: profile.finalAsrTrailingSilence,
            ),
          );
        }
      }
      if (rawFinalTranscription != null &&
          rawTranscription is! StreamingTranscriptionEngine) {
        throw StateError(
          'A final ASR refiner requires a streaming primary engine.',
        );
      }
      final speakers = await SherpaSpeakerAttributionEngine.create(
        modelPath: models.speakerEmbeddingModel,
        similarityThreshold: profile.speakerSimilarityThreshold,
        pendingSpeakerSimilarityThreshold:
            profile.pendingSpeakerSimilarityThreshold,
        speakerSwitchMargin: profile.speakerSwitchMargin,
        maximumSpeakers: profile.maximumSpeakers,
        newSpeakerConfirmationCount: profile.newSpeakerConfirmationCount,
        minimumEmbeddingDuration: profile.minimumSpeakerEmbeddingDuration,
      );
      if (rawTranscription is StreamingTranscriptionEngine) {
        return StreamingDefaultTranscriptionSession(
          audioInput: audio,
          segmenter: vad,
          transcriptionEngine: NormalizingStreamingTranscriptionEngine(
            engine: rawTranscription,
            normalizer: normalizer,
          ),
          finalTranscriptionEngine: rawFinalTranscription == null
              ? null
              : NormalizingTranscriptionEngine(
                  engine: rawFinalTranscription,
                  normalizer: normalizer,
                ),
          maximumRefinementAge: profile.maximumRefinementAge,
          hypothesisPolicy: profile.hypothesisPolicy,
          speakerEngine: speakers,
        );
      }
      final source = SegmentedSpeechTurnSource(
        audioInput: audio,
        segmenter: vad,
      );
      return DefaultTranscriptionSession(
        source: source,
        transcriptionEngine: NormalizingTranscriptionEngine(
          engine: rawTranscription,
          normalizer: normalizer,
        ),
        speakerEngine: speakers,
      );
    } catch (_) {
      await rawFinalTranscription?.close();
      await rawTranscription.close();
      rethrow;
    }
  } catch (_) {
    await audio.close();
    await vad.close();
    rethrow;
  }
}

Future<TranscriptionEngine> _createTranscriptionEngine(
  LiveAsrModelPaths paths, {
  String? languageHint,
}) async {
  if (paths is VoskAsrModelPaths) {
    final isFormalArabic = paths.locale.toLowerCase() == 'ar';
    return VoskTranscriptionEngine.create(
      modelDirectory: paths.modelDirectory,
      locale: paths.locale,
      model: paths.descriptor,
      maximumAlternatives: isFormalArabic ? 3 : 0,
    );
  }
  if (paths is OmnilingualAsrModelPaths) {
    return SherpaOmnilingualTranscriptionEngine.create(
      modelPath: paths.model,
      tokensPath: paths.tokens,
    );
  }
  if (paths is WhisperAsrModelPaths) {
    return SherpaWhisperTranscriptionEngine.create(
      encoderPath: paths.encoder,
      decoderPath: paths.decoder,
      tokensPath: paths.tokens,
      locale: paths.locale,
      model: paths.descriptor,
    );
  }
  if (paths is Qwen3AsrModelPaths) {
    return SherpaQwen3TranscriptionEngine.create(
      convFrontendPath: paths.convFrontend,
      encoderPath: paths.encoder,
      decoderPath: paths.decoder,
      tokenizerPath: paths.tokenizer,
      locale: paths.locale,
      language: languageHint ?? 'Arabic',
    );
  }
  final audar = paths as AudarAsrModelPaths;
  return AudarTranscriptionEngine.create(
    decoderPath: audar.decoder,
    audioProjectorPath: audar.audioProjector,
    locale: audar.locale,
  );
}
