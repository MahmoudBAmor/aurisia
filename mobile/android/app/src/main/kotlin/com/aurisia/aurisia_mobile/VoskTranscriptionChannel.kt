package com.aurisia.aurisia_mobile

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors
import org.json.JSONObject
import org.vosk.Model
import org.vosk.Recognizer

/** Android implementation of Aurisia's model-neutral transcription port. */
class VoskTranscriptionChannel(
    private val context: Context,
    messenger: BinaryMessenger,
) : AutoCloseable {
    private val channel = MethodChannel(messenger, CHANNEL_NAME)
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var model: Model? = null
    private var recognizer: Recognizer? = null
    private var modelPath: String? = null
    private val streamedResults = mutableListOf<Recognition>()
    private var streaming = false
    private var streamedInferenceMilliseconds = 0L
    private var streamedAudioMilliseconds = 0

    init {
        channel.setMethodCallHandler(::handle)
    }

    private fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            INITIALIZE_METHOD -> initialize(call, result)
            TRANSCRIBE_METHOD -> transcribe(call, result)
            START_STREAM_METHOD -> startStream(result)
            ACCEPT_STREAM_FRAME_METHOD -> acceptStreamFrame(call, result)
            FINISH_STREAM_METHOD -> finishStream(result)
            CLOSE_METHOD -> closeFromDart(result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        val requestedPath = try {
            requirePrivateModelDirectory(call.argument<String>("modelPath"))
        } catch (error: Throwable) {
            result.error(INVALID_ARGUMENT, error.message, null)
            return
        }
        val maximumAlternatives = call.argument<Number>("maximumAlternatives")?.toInt() ?: 0
        if (maximumAlternatives !in 0..MAXIMUM_ALTERNATIVES) {
            result.error(
                INVALID_ARGUMENT,
                "Vosk maximumAlternatives must be between 0 and $MAXIMUM_ALTERNATIVES.",
                null,
            )
            return
        }

        worker.execute {
            try {
                if (model == null || modelPath != requestedPath) {
                    closeRuntime()
                    val loadedModel = Model(requestedPath)
                    val loadedRecognizer = try {
                        Recognizer(loadedModel, REQUIRED_SAMPLE_RATE_HZ.toFloat()).also {
                            it.setWords(true)
                            it.setPartialWords(true)
                            it.setMaxAlternatives(maximumAlternatives)
                        }
                    } catch (error: Throwable) {
                        loadedModel.close()
                        throw error
                    }
                    model = loadedModel
                    recognizer = loadedRecognizer
                    modelPath = requestedPath
                } else {
                    recognizer?.setMaxAlternatives(maximumAlternatives)
                }
                succeed(result, null)
            } catch (error: Throwable) {
                fail(result, INITIALIZATION_FAILED, error)
            }
        }
    }

    private fun transcribe(call: MethodCall, result: MethodChannel.Result) {
        val pcm16 = call.argument<ByteArray>("pcm16")
        val sampleRateHz = call.argument<Number>("sampleRateHz")?.toInt()
        if (
            pcm16 == null ||
            pcm16.isEmpty() ||
            pcm16.size % BYTES_PER_SAMPLE != 0 ||
            sampleRateHz != REQUIRED_SAMPLE_RATE_HZ
        ) {
            result.error(
                INVALID_ARGUMENT,
                "Vosk requires non-empty 16 kHz mono PCM16 audio.",
                null,
            )
            return
        }
        val validatedPcm16 = requireNotNull(pcm16)
        val validatedSampleRateHz = requireNotNull(sampleRateHz)

        worker.execute {
            try {
                if (streaming) {
                    throw IllegalStateException(
                        "Turn-based recognition cannot run during a live stream.",
                    )
                }
                val loadedRecognizer = recognizer
                    ?: throw IllegalStateException("The Vosk recognizer is not initialized.")
                val startedAtNanos = SystemClock.elapsedRealtimeNanos()
                val recognition = recognize(
                    loadedRecognizer,
                    validatedPcm16,
                )
                val inferenceMilliseconds =
                    (SystemClock.elapsedRealtimeNanos() - startedAtNanos) / NANOS_PER_MILLISECOND
                val audioMilliseconds =
                    validatedPcm16.size * MILLIS_PER_SECOND /
                        (validatedSampleRateHz * BYTES_PER_SAMPLE)
                Log.i(
                    LOG_TAG,
                    "Decoded ${audioMilliseconds}ms in ${inferenceMilliseconds}ms",
                )
                succeed(
                    result,
                    mapOf(
                        "text" to recognition.text,
                        "confidence" to recognition.confidence,
                        "inferenceMs" to inferenceMilliseconds,
                        "audioMs" to audioMilliseconds,
                    ),
                )
            } catch (error: Throwable) {
                fail(result, RECOGNITION_FAILED, error)
            }
        }
    }

    private fun startStream(result: MethodChannel.Result) {
        worker.execute {
            try {
                val loadedRecognizer = recognizer
                    ?: throw IllegalStateException("The Vosk recognizer is not initialized.")
                if (streaming) {
                    throw IllegalStateException("The Vosk live stream is already active.")
                }
                loadedRecognizer.reset()
                streamedResults.clear()
                streamedInferenceMilliseconds = 0L
                streamedAudioMilliseconds = 0
                streaming = true
                succeed(result, null)
            } catch (error: Throwable) {
                fail(result, STREAMING_FAILED, error)
            }
        }
    }

    private fun acceptStreamFrame(call: MethodCall, result: MethodChannel.Result) {
        val pcm16 = call.argument<ByteArray>("pcm16")
        val sampleRateHz = call.argument<Number>("sampleRateHz")?.toInt()
        if (
            pcm16 == null ||
            pcm16.isEmpty() ||
            pcm16.size % BYTES_PER_SAMPLE != 0 ||
            sampleRateHz != REQUIRED_SAMPLE_RATE_HZ
        ) {
            result.error(
                INVALID_ARGUMENT,
                "Vosk requires non-empty 16 kHz mono PCM16 audio.",
                null,
            )
            return
        }
        val validatedPcm16 = requireNotNull(pcm16)

        worker.execute {
            try {
                val loadedRecognizer = recognizer
                    ?: throw IllegalStateException("The Vosk recognizer is not initialized.")
                if (!streaming) {
                    throw IllegalStateException("The Vosk live stream is not active.")
                }
                val startedAtNanos = SystemClock.elapsedRealtimeNanos()
                if (loadedRecognizer.acceptWaveForm(validatedPcm16, validatedPcm16.size)) {
                    streamedResults += parseResult(loadedRecognizer.result)
                }
                val partial = parsePartialResult(loadedRecognizer.partialResult)
                val recognition = combineRecognitions(streamedResults + partial)
                val inferenceMilliseconds =
                    (SystemClock.elapsedRealtimeNanos() - startedAtNanos) /
                        NANOS_PER_MILLISECOND
                val audioMilliseconds =
                    validatedPcm16.size * MILLIS_PER_SECOND /
                        (REQUIRED_SAMPLE_RATE_HZ * BYTES_PER_SAMPLE)
                streamedInferenceMilliseconds += inferenceMilliseconds
                streamedAudioMilliseconds += audioMilliseconds
                succeed(
                    result,
                    recognition.toPlatformResult(
                        inferenceMilliseconds = inferenceMilliseconds,
                        audioMilliseconds = audioMilliseconds,
                    ),
                )
            } catch (error: Throwable) {
                abortStream()
                fail(result, STREAMING_FAILED, error)
            }
        }
    }

    private fun finishStream(result: MethodChannel.Result) {
        worker.execute {
            try {
                val loadedRecognizer = recognizer
                    ?: throw IllegalStateException("The Vosk recognizer is not initialized.")
                if (!streaming) {
                    throw IllegalStateException("The Vosk live stream is not active.")
                }
                val startedAtNanos = SystemClock.elapsedRealtimeNanos()
                streamedResults += parseResult(loadedRecognizer.finalResult)
                val recognition = combineRecognitions(streamedResults)
                val inferenceMilliseconds =
                    (SystemClock.elapsedRealtimeNanos() - startedAtNanos) /
                        NANOS_PER_MILLISECOND
                streamedInferenceMilliseconds += inferenceMilliseconds
                val totalInferenceMilliseconds = streamedInferenceMilliseconds
                val totalAudioMilliseconds = streamedAudioMilliseconds
                val platformResult = recognition.toPlatformResult(
                    inferenceMilliseconds = totalInferenceMilliseconds,
                    audioMilliseconds = totalAudioMilliseconds,
                )
                Log.i(
                    LOG_TAG,
                    "Stream decoded ${totalAudioMilliseconds}ms in " +
                        "${totalInferenceMilliseconds}ms",
                )
                loadedRecognizer.reset()
                streamedResults.clear()
                streamedInferenceMilliseconds = 0L
                streamedAudioMilliseconds = 0
                streaming = false
                succeed(result, platformResult)
            } catch (error: Throwable) {
                abortStream()
                fail(result, STREAMING_FAILED, error)
            }
        }
    }

    private fun recognize(recognizer: Recognizer, pcm16: ByteArray): Recognition {
        val completed = mutableListOf<Recognition>()
        try {
            var offset = 0
            while (offset < pcm16.size) {
                val end = minOf(offset + DECODE_CHUNK_BYTES, pcm16.size)
                val chunk = pcm16.copyOfRange(offset, end)
                if (recognizer.acceptWaveForm(chunk, chunk.size)) {
                    completed += parseResult(recognizer.result)
                }
                offset = end
            }
            completed += parseResult(recognizer.finalResult)
        } finally {
            recognizer.reset()
        }

        return combineRecognitions(completed)
    }

    private fun parseResult(raw: String): Recognition {
        val json = JSONObject(raw)
        return parseRecognition(json, textKey = "text", wordsKey = "result")
    }

    private fun parsePartialResult(raw: String): Recognition {
        val json = JSONObject(raw)
        return parseRecognition(
            json,
            textKey = "partial",
            wordsKey = "partial_result",
        )
    }

    private fun parseRecognition(
        json: JSONObject,
        textKey: String,
        wordsKey: String,
    ): Recognition {
        val alternativesJson = json.optJSONArray("alternatives")
        if (alternativesJson != null) {
            val alternatives = buildList {
                for (index in 0 until alternativesJson.length()) {
                    val alternative = alternativesJson.optJSONObject(index) ?: continue
                    val text = alternative.optString("text", "").trim()
                    if (text.isEmpty()) {
                        continue
                    }
                    val rawConfidence = alternative.optDouble("confidence", Double.NaN)
                    add(
                        RecognitionCandidate(
                            text = text,
                            decoderScore = rawConfidence
                                .takeIf { confidence -> confidence.isFinite() }
                        ),
                    )
                }
            }
            if (alternatives.isNotEmpty()) {
                val best = alternatives.first()
                return Recognition(
                    text = best.text,
                    confidence = null,
                    alternatives = alternatives,
                )
            }
        }
        val text = json.optString(textKey, "").trim()
        val words = json.optJSONArray(wordsKey)
        val confidences = mutableListOf<Double>()
        if (words != null) {
            for (index in 0 until words.length()) {
                val confidence = words.optJSONObject(index)?.optDouble("conf", Double.NaN)
                if (confidence != null && confidence.isFinite()) {
                    confidences += confidence.coerceIn(0.0, 1.0)
                }
            }
        }
        return Recognition(
            text = text,
            confidence = confidences.takeIf { it.isNotEmpty() }?.average(),
        )
    }

    private fun combineRecognitions(values: List<Recognition>): Recognition {
        val nonEmpty = values.filter { recognition -> recognition.text.isNotBlank() }
        if (nonEmpty.isEmpty()) {
            return Recognition(text = "", confidence = null)
        }
        var beam = listOf(RecognitionCandidate(text = "", decoderScore = null))
        for (recognition in nonEmpty) {
            val options = recognition.alternatives.ifEmpty {
                listOf(
                    RecognitionCandidate(
                        text = recognition.text,
                        decoderScore = null,
                    ),
                )
            }
            beam = beam
                .flatMap { prefix ->
                    options.map { option ->
                        RecognitionCandidate(
                            text = listOf(prefix.text, option.text)
                                .filter { part -> part.isNotBlank() }
                                .joinToString(" "),
                            decoderScore = combineDecoderScore(
                                prefix.decoderScore,
                                option.decoderScore,
                            ),
                        )
                    }
                }
                .sortedWith(
                    compareByDescending<RecognitionCandidate> {
                        it.decoderScore ?: Double.NEGATIVE_INFINITY
                    }.thenBy { candidate -> candidate.text },
                )
                .take(MAXIMUM_ALTERNATIVES)
        }
        val best = beam.first()
        return Recognition(
            text = best.text,
            confidence = combineConfidence(nonEmpty),
            alternatives = beam.takeIf { candidates -> candidates.size > 1 }.orEmpty(),
        )
    }

    private fun combineDecoderScore(left: Double?, right: Double?): Double? = when {
        left == null -> right
        right == null -> left
        else -> left + right
    }

    private fun combineConfidence(recognitions: List<Recognition>): Double? {
        if (recognitions.any { recognition -> recognition.confidence == null }) {
            return null
        }
        return recognitions.fold(1.0) { combined, recognition ->
            combined * requireNotNull(recognition.confidence)
        }
    }

    private fun Recognition.toPlatformResult(
        inferenceMilliseconds: Long,
        audioMilliseconds: Int? = null,
    ): Map<String, Any?> = buildMap {
        put("text", text)
        put("confidence", confidence)
        if (alternatives.size > 1) {
            put(
                "alternatives",
                alternatives.map { candidate ->
                    mapOf("text" to candidate.text)
                },
            )
        }
        put("inferenceMs", inferenceMilliseconds)
        if (audioMilliseconds != null) {
            put("audioMs", audioMilliseconds)
        }
    }

    private fun closeFromDart(result: MethodChannel.Result) {
        worker.execute {
            try {
                closeRuntime()
                succeed(result, null)
            } catch (error: Throwable) {
                fail(result, CLOSE_FAILED, error)
            }
        }
    }

    private fun requirePrivateModelDirectory(value: String?): String {
        if (value.isNullOrBlank()) {
            throw IllegalArgumentException("The Vosk model path is required.")
        }
        val directory = File(value).canonicalFile
        val modelPackRoot = File(context.filesDir, "model_packs").canonicalFile
        if (
            !directory.isDirectory ||
            !directory.path.startsWith("${modelPackRoot.path}${File.separator}")
        ) {
            throw IllegalArgumentException("The Vosk model path is not an installed model pack.")
        }
        REQUIRED_COMMON_MODEL_FILES.forEach { relativePath ->
            if (!File(directory, relativePath).isFile) {
                throw IllegalArgumentException("The Vosk model is missing $relativePath.")
            }
        }
        if (
            REQUIRED_GRAPH_LAYOUTS.none { layout ->
                layout.all { relativePath -> File(directory, relativePath).isFile }
            }
        ) {
            throw IllegalArgumentException(
                "The Vosk model has neither a compact nor a legacy decoding graph.",
            )
        }
        return directory.path
    }

    private fun succeed(result: MethodChannel.Result, value: Any?) {
        mainHandler.post { result.success(value) }
    }

    private fun fail(result: MethodChannel.Result, code: String, error: Throwable) {
        val message = error.describeCauseChain()
        Log.e(LOG_TAG, "$code: $message", error)
        mainHandler.post {
            result.error(
                code,
                message,
                mapOf("nativeErrorType" to error.javaClass.name),
            )
        }
    }

    private fun Throwable.describeCauseChain(): String =
        generateSequence(this) { current -> current.cause }
            .take(MAX_REPORTED_CAUSES)
            .joinToString(" caused by ") { current ->
                val description = current.message?.takeIf { message -> message.isNotBlank() }
                if (description == null) {
                    current.javaClass.name
                } else {
                    "${current.javaClass.name}: $description"
                }
            }

    private fun closeRuntime() {
        streamedResults.clear()
        streaming = false
        streamedInferenceMilliseconds = 0L
        streamedAudioMilliseconds = 0
        recognizer?.close()
        recognizer = null
        model?.close()
        model = null
        modelPath = null
    }

    private fun abortStream() {
        streamedResults.clear()
        streaming = false
        streamedInferenceMilliseconds = 0L
        streamedAudioMilliseconds = 0
        try {
            recognizer?.reset()
        } catch (resetError: Throwable) {
            Log.e(LOG_TAG, "Could not reset the failed Vosk stream.", resetError)
        }
    }

    override fun close() {
        channel.setMethodCallHandler(null)
        worker.execute {
            closeRuntime()
        }
        worker.shutdown()
    }

    private data class Recognition(
        val text: String,
        val confidence: Double?,
        val alternatives: List<RecognitionCandidate> = emptyList(),
    )

    private data class RecognitionCandidate(
        val text: String,
        val decoderScore: Double?,
    )

    private companion object {
        const val CHANNEL_NAME = "com.aurisia/asr/vosk"
        const val INITIALIZE_METHOD = "initialize"
        const val TRANSCRIBE_METHOD = "transcribe"
        const val START_STREAM_METHOD = "startStream"
        const val ACCEPT_STREAM_FRAME_METHOD = "acceptStreamFrame"
        const val FINISH_STREAM_METHOD = "finishStream"
        const val CLOSE_METHOD = "close"
        const val INVALID_ARGUMENT = "INVALID_ARGUMENT"
        const val INITIALIZATION_FAILED = "VOSK_INITIALIZATION_FAILED"
        const val RECOGNITION_FAILED = "VOSK_RECOGNITION_FAILED"
        const val STREAMING_FAILED = "VOSK_STREAMING_FAILED"
        const val CLOSE_FAILED = "VOSK_CLOSE_FAILED"
        const val REQUIRED_SAMPLE_RATE_HZ = 16_000
        const val BYTES_PER_SAMPLE = 2
        const val DECODE_CHUNK_BYTES = 3_200
        const val MILLIS_PER_SECOND = 1_000
        const val NANOS_PER_MILLISECOND = 1_000_000
        const val MAX_REPORTED_CAUSES = 5
        const val MAXIMUM_ALTERNATIVES = 3
        const val LOG_TAG = "AurisiaVosk"
        val REQUIRED_COMMON_MODEL_FILES = listOf(
            "am/final.mdl",
            "conf/model.conf",
            "graph/words.txt",
        )
        val REQUIRED_GRAPH_LAYOUTS = listOf(
            listOf("graph/Gr.fst", "graph/HCLr.fst"),
            listOf("graph/HCLG.fst"),
        )
    }
}
