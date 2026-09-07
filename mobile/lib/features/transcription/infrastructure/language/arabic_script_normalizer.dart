import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/ports/transcript_text_normalizer.dart';

class ArabicScriptNormalizer implements TranscriptTextNormalizer {
  ArabicScriptNormalizer(
    Map<String, String> replacements, {
    this.rejectCorruptMixedScriptText = false,
  }) : _replacements =
           replacements.entries
               .where(
                 (entry) =>
                     entry.key.trim().isNotEmpty &&
                     entry.value.trim().isNotEmpty,
               )
               .map((entry) => MapEntry(entry.key.trim(), entry.value.trim()))
               .toList(growable: false)
             ..sort(
               (left, right) => right.key.length.compareTo(left.key.length),
             );

  final List<MapEntry<String, String>> _replacements;
  final bool rejectCorruptMixedScriptText;

  static Future<ArabicScriptNormalizer> load({
    AssetBundle? assets,
    String assetPath = 'assets/language_packs/aeb-TN/display_lexicon.json',
  }) async {
    final raw = await (assets ?? rootBundle).loadString(assetPath);
    final decoded = jsonDecode(raw);
    if (decoded is! Map<Object?, Object?> || decoded['schema_version'] != 1) {
      throw const FormatException('Unsupported Arabic display lexicon.');
    }
    final rawReplacements = decoded['replacements'];
    if (rawReplacements is! Map<Object?, Object?>) {
      throw const FormatException('Arabic display replacements are missing.');
    }
    final replacements = <String, String>{};
    for (final entry in rawReplacements.entries) {
      final source = entry.key;
      final target = entry.value;
      if (source is! String || target is! String) {
        throw const FormatException(
          'Arabic display replacements must map strings to strings.',
        );
      }
      replacements[source] = target;
    }
    final rejectCorruptMixedScriptText =
        decoded['reject_corrupt_mixed_script_text'] ?? false;
    if (rejectCorruptMixedScriptText is! bool) {
      throw const FormatException(
        'reject_corrupt_mixed_script_text must be a boolean.',
      );
    }
    return ArabicScriptNormalizer(
      replacements,
      rejectCorruptMixedScriptText: rejectCorruptMixedScriptText,
    );
  }

  @override
  String normalize(String text) {
    var normalized = text;
    if (rejectCorruptMixedScriptText &&
        normalized.split(RegExp(r'\s+')).any(_isCorruptMixedScriptToken)) {
      return '';
    }
    for (final replacement in _replacements) {
      final pattern = RegExp(
        r'(?<![\w-])' + RegExp.escape(replacement.key) + r'(?![\w-])',
        caseSensitive: false,
        unicode: true,
      );
      normalized = normalized.replaceAll(pattern, replacement.value);
    }
    return normalized.trim().replaceAll(RegExp(r'\s+'), ' ');
  }
}

bool _isCorruptMixedScriptToken(String token) {
  if (token.contains('\uFFFD')) {
    return true;
  }
  final hasArabic = RegExp(r'[\u0600-\u06FF]', unicode: true).hasMatch(token);
  final hasLatin = RegExp(r'[A-Za-z]', unicode: true).hasMatch(token);
  return hasArabic && hasLatin;
}
