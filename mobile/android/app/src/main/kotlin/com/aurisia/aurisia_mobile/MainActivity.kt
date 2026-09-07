package com.aurisia.aurisia_mobile

import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedInputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.Executors
import java.util.zip.ZipInputStream

class MainActivity : FlutterActivity() {
    private val modelInstaller = Executors.newSingleThreadExecutor()
    private var voskChannel: VoskTranscriptionChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MODEL_PACK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            if (call.method != MATERIALIZE_METHOD) {
                result.notImplemented()
                return@setMethodCallHandler
            }
            installModelPack(call, result)
        }
        voskChannel = VoskTranscriptionChannel(
            context = this,
            messenger = flutterEngine.dartExecutor.binaryMessenger,
        )
    }

    override fun onDestroy() {
        voskChannel?.close()
        voskChannel = null
        modelInstaller.shutdownNow()
        super.onDestroy()
    }

    private fun installModelPack(call: MethodCall, result: MethodChannel.Result) {
        modelInstaller.execute {
            try {
                val packId = requireSafeName(call.argument<String>("packId"), "packId")
                val version = requireSafeName(call.argument<String>("version"), "version")
                val assetRoot = requireAssetRoot(call.argument<String>("assetRoot"))
                val artifacts = parseArtifacts(call.argument<List<Map<String, Any?>>>("artifacts"))
                val destination = File(filesDir, "model_packs/$packId/$version")
                if (!destination.exists() && !destination.mkdirs()) {
                    throw IllegalStateException("Could not create the model pack directory.")
                }

                val paths = artifacts.associate { artifact ->
                    artifact.role to materializeArtifact(destination, assetRoot, artifact).absolutePath
                }
                runOnUiThread { result.success(paths) }
            } catch (error: Throwable) {
                runOnUiThread {
                    result.error(
                        "MODEL_PACK_INSTALL_FAILED",
                        error.message ?: "Could not install the offline models.",
                        null,
                    )
                }
            }
        }
    }

    private fun materializeArtifact(
        destination: File,
        assetRoot: String,
        artifact: Artifact,
    ): File = when (artifact.kind) {
        ArtifactKind.FILE -> materializeFileArtifact(destination, assetRoot, artifact)
        ArtifactKind.ZIP_DIRECTORY -> materializeZipDirectory(destination, assetRoot, artifact)
    }

    private fun materializeFileArtifact(
        destination: File,
        assetRoot: String,
        artifact: Artifact,
    ): File {
        val target = File(destination, artifact.path)
        ensureParentDirectory(target)
        val checksumMarker = File(destination, "${artifact.path}.sha256")
        if (
            target.isFile &&
            target.length() == artifact.sizeBytes &&
            checksumMarker.isFile &&
            checksumMarker.readText().trim().equals(artifact.sha256, ignoreCase = true)
        ) {
            return target
        }

        val partial = File(destination, "${artifact.path}.partial")
        ensureParentDirectory(partial)
        deleteFileIfPresent(partial, "Could not replace an incomplete model file.")
        copyVerifiedAsset(assetRoot, artifact, partial)

        deleteFileIfPresent(target, "Could not replace the installed model file.")
        if (!partial.renameTo(target)) {
            partial.delete()
            throw IllegalStateException("Could not commit the installed model file.")
        }
        checksumMarker.writeText(artifact.sha256)
        return target
    }

    private fun materializeZipDirectory(
        destination: File,
        assetRoot: String,
        artifact: Artifact,
    ): File {
        val outputPath = requireNotNull(artifact.outputPath)
        val outputSha256 = requireNotNull(artifact.outputSha256)
        val outputSizeBytes = requireNotNull(artifact.outputSizeBytes)
        val archivePrefix = requireNotNull(artifact.archivePrefix)
        val target = File(destination, outputPath)
        val checksumMarker = File(destination, "$outputPath.tree.sha256")
        val markerValue = "$outputSha256:$outputSizeBytes"
        if (
            target.isDirectory &&
            checksumMarker.isFile &&
            checksumMarker.readText().trim() == markerValue
        ) {
            return target
        }

        val archive = File(destination, "${artifact.path}.partial")
        val partialDirectory = File(destination, "$outputPath.partial")
        ensureParentDirectory(archive)
        deleteFileIfPresent(archive, "Could not replace an incomplete model archive.")
        if (partialDirectory.exists() && !partialDirectory.deleteRecursively()) {
            throw IllegalStateException("Could not replace an incomplete model directory.")
        }
        if (!partialDirectory.mkdirs()) {
            throw IllegalStateException("Could not create the temporary model directory.")
        }

        try {
            copyVerifiedAsset(assetRoot, artifact, archive)
            extractVerifiedZip(archive, partialDirectory, archivePrefix)
            val fingerprint = fingerprintTree(partialDirectory)
            if (
                fingerprint.sizeBytes != outputSizeBytes ||
                fingerprint.sha256 != outputSha256
            ) {
                throw IllegalStateException(
                    "Extracted model verification failed for ${artifact.path}.",
                )
            }

            if (target.exists() && !target.deleteRecursively()) {
                throw IllegalStateException("Could not replace the installed model directory.")
            }
            if (!partialDirectory.renameTo(target)) {
                throw IllegalStateException("Could not commit the installed model directory.")
            }
            ensureParentDirectory(checksumMarker)
            checksumMarker.writeText(markerValue)
            return target
        } finally {
            archive.delete()
            if (partialDirectory.exists()) {
                partialDirectory.deleteRecursively()
            }
        }
    }

    private fun copyVerifiedAsset(assetRoot: String, artifact: Artifact, target: File) {
        val assetKey = FlutterInjector.instance().flutterLoader().getLookupKeyForAsset(
            "$assetRoot/${artifact.path}",
        )
        val digest = MessageDigest.getInstance("SHA-256")
        var bytesWritten = 0L
        try {
            assets.open(assetKey).use { input ->
                FileOutputStream(target).use { output ->
                    val buffer = ByteArray(COPY_BUFFER_BYTES)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) {
                            break
                        }
                        output.write(buffer, 0, count)
                        digest.update(buffer, 0, count)
                        bytesWritten += count
                    }
                    output.fd.sync()
                }
            }
        } catch (error: Throwable) {
            target.delete()
            throw error
        }

        val actualSha256 = digest.digest().toHex()
        if (bytesWritten != artifact.sizeBytes || actualSha256 != artifact.sha256) {
            target.delete()
            throw IllegalStateException("Bundled model verification failed for ${artifact.path}.")
        }
    }

    private fun extractVerifiedZip(archive: File, destination: File, archivePrefix: String) {
        val prefix = "$archivePrefix/"
        var extractedFiles = 0
        ZipInputStream(BufferedInputStream(FileInputStream(archive))).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                val entryName = entry.name
                if (entryName.contains('\\')) {
                    throw IllegalStateException("Model archive contains an invalid path.")
                }
                if (entryName == archivePrefix || entryName == prefix) {
                    zip.closeEntry()
                    continue
                }
                if (!entryName.startsWith(prefix)) {
                    throw IllegalStateException("Model archive has an unexpected root directory.")
                }
                val relativePath = requireSafeRelativePath(
                    entryName.removePrefix(prefix).trimEnd('/'),
                    "archive entry",
                )
                val output = File(destination, relativePath)
                if (entry.isDirectory) {
                    if (!output.exists() && !output.mkdirs()) {
                        throw IllegalStateException("Could not create a model subdirectory.")
                    }
                } else {
                    ensureParentDirectory(output)
                    FileOutputStream(output).use { file -> zip.copyTo(file, COPY_BUFFER_BYTES) }
                    extractedFiles += 1
                }
                zip.closeEntry()
            }
        }
        if (extractedFiles == 0) {
            throw IllegalStateException("Model archive did not contain any files.")
        }
    }

    private fun fingerprintTree(root: File): TreeFingerprint {
        val files = root.walkTopDown().filter { it.isFile }.toList().sortedBy { file ->
            file.relativeTo(root).invariantSeparatorsPath
        }
        if (files.isEmpty()) {
            throw IllegalStateException("Extracted model directory is empty.")
        }

        val digest = MessageDigest.getInstance("SHA-256")
        var totalSize = 0L
        val buffer = ByteArray(COPY_BUFFER_BYTES)
        files.forEach { file ->
            val relativePath = file.relativeTo(root).invariantSeparatorsPath
            digest.update(relativePath.toByteArray(Charsets.UTF_8))
            digest.update(0.toByte())
            digest.update(file.length().toString().toByteArray(Charsets.US_ASCII))
            digest.update(0.toByte())
            FileInputStream(file).use { input ->
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) {
                        break
                    }
                    digest.update(buffer, 0, count)
                }
            }
            totalSize += file.length()
        }
        return TreeFingerprint(totalSize, digest.digest().toHex())
    }

    private fun parseArtifacts(raw: List<Map<String, Any?>>?): List<Artifact> {
        if (raw.isNullOrEmpty()) {
            throw IllegalArgumentException("The model pack has no artifacts.")
        }
        val artifacts = raw.map { value ->
            val size = value["sizeBytes"] as? Number
                ?: throw IllegalArgumentException("A model artifact has no size.")
            val sha256 = value["sha256"] as? String
                ?: throw IllegalArgumentException("A model artifact has no checksum.")
            if (!SHA_256.matches(sha256)) {
                throw IllegalArgumentException("A model artifact checksum is invalid.")
            }
            val kind = when (value["kind"] as? String ?: "file") {
                "file" -> ArtifactKind.FILE
                "zip_directory" -> ArtifactKind.ZIP_DIRECTORY
                else -> throw IllegalArgumentException("A model artifact kind is invalid.")
            }
            val artifact = Artifact(
                role = requireSafeName(value["role"] as? String, "artifact role"),
                path = requireSafeRelativePath(value["path"] as? String, "artifact path"),
                sha256 = sha256.lowercase(),
                sizeBytes = size.toLong().also {
                    if (it <= 0) {
                        throw IllegalArgumentException("A model artifact size is invalid.")
                    }
                },
                kind = kind,
                outputPath = value["outputPath"] as? String,
                outputSha256 = value["outputSha256"] as? String,
                outputSizeBytes = (value["outputSizeBytes"] as? Number)?.toLong(),
                archivePrefix = value["archivePrefix"] as? String,
            )
            if (kind == ArtifactKind.ZIP_DIRECTORY) {
                requireSafeRelativePath(artifact.outputPath, "archive output path")
                requireSafeRelativePath(artifact.archivePrefix, "archive prefix")
                if (
                    artifact.outputSha256 == null ||
                    !SHA_256.matches(artifact.outputSha256)
                ) {
                    throw IllegalArgumentException("A model archive output checksum is invalid.")
                }
                if (artifact.outputSizeBytes == null || artifact.outputSizeBytes <= 0) {
                    throw IllegalArgumentException("A model archive output size is invalid.")
                }
            }
            artifact
        }
        if (artifacts.map { artifact -> artifact.role }.toSet().size != artifacts.size) {
            throw IllegalArgumentException("Model artifact roles must be unique.")
        }
        return artifacts
    }

    private fun requireSafeName(value: String?, label: String): String {
        if (value == null || value == "." || value == ".." || !SAFE_NAME.matches(value)) {
            throw IllegalArgumentException("The $label is invalid.")
        }
        return value
    }

    private fun requireSafeRelativePath(value: String?, label: String): String {
        if (
            value.isNullOrEmpty() ||
            value.startsWith('/') ||
            value.contains('\\') ||
            value.split('/').any { segment ->
                segment.isEmpty() ||
                    segment == "." ||
                    segment == ".." ||
                    !SAFE_NAME.matches(segment)
            }
        ) {
            throw IllegalArgumentException("The $label is invalid.")
        }
        return value
    }

    private fun requireAssetRoot(value: String?): String {
        if (value == null || !SAFE_ASSET_ROOT.matches(value) || value.contains("..")) {
            throw IllegalArgumentException("The model asset root is invalid.")
        }
        return value
    }

    private fun ensureParentDirectory(file: File) {
        val parent = file.parentFile
            ?: throw IllegalStateException("A model path has no parent directory.")
        if (!parent.exists() && !parent.mkdirs()) {
            throw IllegalStateException("Could not create a model subdirectory.")
        }
    }

    private fun deleteFileIfPresent(file: File, message: String) {
        if (file.exists() && !file.delete()) {
            throw IllegalStateException(message)
        }
    }

    private fun ByteArray.toHex(): String = joinToString(separator = "") { byte ->
        (byte.toInt() and 0xff).toString(16).padStart(2, '0')
    }

    private enum class ArtifactKind {
        FILE,
        ZIP_DIRECTORY,
    }

    private data class Artifact(
        val role: String,
        val path: String,
        val sha256: String,
        val sizeBytes: Long,
        val kind: ArtifactKind,
        val outputPath: String?,
        val outputSha256: String?,
        val outputSizeBytes: Long?,
        val archivePrefix: String?,
    )

    private data class TreeFingerprint(
        val sizeBytes: Long,
        val sha256: String,
    )

    private companion object {
        const val MODEL_PACK_CHANNEL = "com.aurisia/model_pack"
        const val MATERIALIZE_METHOD = "materializeBundledPack"
        const val COPY_BUFFER_BYTES = 1024 * 1024
        val SAFE_NAME = Regex("^[A-Za-z0-9._-]+$")
        val SAFE_ASSET_ROOT = Regex("^[A-Za-z0-9._/-]+$")
        val SHA_256 = Regex("^[a-fA-F0-9]{64}$")
    }
}
