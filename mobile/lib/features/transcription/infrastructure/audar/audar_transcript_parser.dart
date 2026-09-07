final RegExp _protocolPrefix = RegExp(
  r'^\s*language\s+([A-Za-z]+)\s*(?:<asr_text>)?\s*',
  caseSensitive: false,
);

/// Removes Audar's machine-readable protocol prefix from visible captions.
///
/// A `language None<asr_text>` verdict deliberately wins over any trailing
/// decoder output: the model uses it to signal silence or non-speech.
String parseAudarTranscript(String raw) {
  final match = _protocolPrefix.firstMatch(raw);
  if (match != null && match.group(1)?.toLowerCase() == 'none') {
    return '';
  }

  var text = match == null ? raw : raw.substring(match.end);
  text = text.replaceFirst(RegExp(r'^\s*<asr_text>\s*'), '');
  return text.trim();
}
