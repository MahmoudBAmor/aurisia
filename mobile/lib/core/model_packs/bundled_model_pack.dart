import 'dart:convert';

import 'package:flutter/services.dart';

enum ModelArtifactKind {
  file('file'),
  zipDirectory('zip_directory');

  const ModelArtifactKind(this.manifestValue);

  final String manifestValue;

  static ModelArtifactKind fromManifest(Object? value) {
    final name = value ?? 'file';
    return ModelArtifactKind.values.firstWhere(
      (kind) => kind.manifestValue == name,
      orElse: () =>
          throw const FormatException('Model artifact kind is not supported.'),
    );
  }
}

class ModelArtifact {
  const ModelArtifact({
    required this.role,
    required this.path,
    required this.sha256,
    required this.sizeBytes,
    this.kind = ModelArtifactKind.file,
    this.outputPath,
    this.outputSha256,
    this.outputSizeBytes,
    this.archivePrefix,
  });

  factory ModelArtifact.fromJson(Map<String, Object?> json) {
    final role = _requiredString(json, 'role');
    final path = _requiredString(json, 'path');
    final sha256 = _requiredString(json, 'sha256').toLowerCase();
    final sizeBytes = json['size_bytes'];
    final kind = ModelArtifactKind.fromManifest(json['kind']);

    if (!_safeName.hasMatch(role)) {
      throw const FormatException('Model artifact role is not safe.');
    }
    if (!_isSafeRelativePath(path)) {
      throw const FormatException('Model artifact path is not safe.');
    }
    if (!_sha256.hasMatch(sha256)) {
      throw const FormatException('Model artifact SHA-256 is invalid.');
    }
    if (sizeBytes is! int || sizeBytes <= 0) {
      throw const FormatException('Model artifact size must be positive.');
    }

    if (kind == ModelArtifactKind.file) {
      return ModelArtifact(
        role: role,
        path: path,
        sha256: sha256,
        sizeBytes: sizeBytes,
      );
    }

    final outputPath = _requiredString(json, 'output_path');
    final outputSha256 = _requiredString(json, 'output_sha256').toLowerCase();
    final outputSizeBytes = json['output_size_bytes'];
    final archivePrefix = _requiredString(json, 'archive_prefix');
    if (!_isSafeRelativePath(outputPath) ||
        !_isSafeRelativePath(archivePrefix)) {
      throw const FormatException(
        'Model archive output paths must be safe and relative.',
      );
    }
    if (!_sha256.hasMatch(outputSha256)) {
      throw const FormatException('Model archive output SHA-256 is invalid.');
    }
    if (outputSizeBytes is! int || outputSizeBytes <= 0) {
      throw const FormatException(
        'Model archive output size must be positive.',
      );
    }

    return ModelArtifact(
      role: role,
      path: path,
      sha256: sha256,
      sizeBytes: sizeBytes,
      kind: kind,
      outputPath: outputPath,
      outputSha256: outputSha256,
      outputSizeBytes: outputSizeBytes,
      archivePrefix: archivePrefix,
    );
  }

  static final RegExp _safeName = RegExp(r'^[A-Za-z0-9._-]+$');
  static final RegExp _sha256 = RegExp(r'^[a-f0-9]{64}$');

  final String role;
  final String path;
  final String sha256;
  final int sizeBytes;
  final ModelArtifactKind kind;
  final String? outputPath;
  final String? outputSha256;
  final int? outputSizeBytes;
  final String? archivePrefix;

  int get installedSizeBytes => outputSizeBytes ?? sizeBytes;

  Map<String, Object> toPlatformArguments() {
    final arguments = <String, Object>{
      'role': role,
      'path': path,
      'sha256': sha256,
      'sizeBytes': sizeBytes,
      'kind': kind.manifestValue,
    };
    if (kind == ModelArtifactKind.zipDirectory) {
      arguments.addAll(<String, Object>{
        'outputPath': outputPath!,
        'outputSha256': outputSha256!,
        'outputSizeBytes': outputSizeBytes!,
        'archivePrefix': archivePrefix!,
      });
    }
    return arguments;
  }
}

class BundledModelPack {
  const BundledModelPack({
    required this.packId,
    required this.version,
    required this.locale,
    required this.runtime,
    required this.assetRoot,
    required this.artifacts,
  });

  factory BundledModelPack.fromJson({
    required Map<String, Object?> json,
    required String assetRoot,
  }) {
    if (json['schema_version'] != 1) {
      throw const FormatException('Unsupported model pack schema.');
    }
    final packId = _requiredString(json, 'pack_id');
    if (!_isSafeName(packId)) {
      throw const FormatException('Model pack identifier is not safe.');
    }
    final rawArtifacts = json['artifacts'];
    if (rawArtifacts is! List<Object?> || rawArtifacts.isEmpty) {
      throw const FormatException('Model pack has no artifacts.');
    }

    final artifacts = rawArtifacts
        .map((raw) {
          if (raw is! Map<Object?, Object?>) {
            throw const FormatException('Invalid model artifact.');
          }
          return ModelArtifact.fromJson(
            raw.map((key, value) => MapEntry(key.toString(), value)),
          );
        })
        .toList(growable: false);
    if (artifacts.map((artifact) => artifact.role).toSet().length !=
        artifacts.length) {
      throw const FormatException('Model artifact roles must be unique.');
    }

    return BundledModelPack(
      packId: packId,
      version: _requiredString(json, 'version'),
      locale: _requiredString(json, 'locale'),
      runtime: _requiredString(json, 'runtime'),
      assetRoot: assetRoot,
      artifacts: artifacts,
    );
  }

  final String packId;
  final String version;
  final String locale;
  final String runtime;
  final String assetRoot;
  final List<ModelArtifact> artifacts;

  int get installedSizeBytes => artifacts.fold(
    0,
    (total, artifact) => total + artifact.installedSizeBytes,
  );

  int get bundledSizeBytes =>
      artifacts.fold(0, (total, artifact) => total + artifact.sizeBytes);
}

class BundledModelPackRepository {
  BundledModelPackRepository({AssetBundle? assets})
    : _assets = assets ?? rootBundle;

  final AssetBundle _assets;

  Future<BundledModelPack> load({
    String assetRoot = 'assets/model_packs/aeb-TN-vosk-full',
  }) async {
    final raw = await _assets.loadString('$assetRoot/manifest.json');
    final decoded = jsonDecode(raw);
    if (decoded is! Map<Object?, Object?>) {
      throw const FormatException('Model pack manifest must be an object.');
    }
    return BundledModelPack.fromJson(
      json: decoded.map((key, value) => MapEntry(key.toString(), value)),
      assetRoot: assetRoot,
    );
  }
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('Model pack field "$key" is required.');
  }
  return value;
}

bool _isSafeRelativePath(String value) {
  if (value.isEmpty || value.startsWith('/') || value.contains(r'\')) {
    return false;
  }
  return value
      .split('/')
      .every((segment) => segment.isNotEmpty && _isSafeName(segment));
}

bool _isSafeName(String value) =>
    value != '.' && value != '..' && ModelArtifact._safeName.hasMatch(value);
