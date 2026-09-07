import 'package:aurisia_mobile/features/transcription/infrastructure/audar/audar_transcript_parser.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes the Audar language protocol prefix', () {
    expect(
      parseAudarTranscript(
        'language Arabic<asr_text>لا إله إلا الله وحده لا شريك له',
      ),
      'لا إله إلا الله وحده لا شريك له',
    );
  });

  test('maps the Audar no-speech verdict to an empty caption', () {
    expect(parseAudarTranscript('language None<asr_text>كلام مكرر'), isEmpty);
  });

  test('preserves plain model output without a protocol prefix', () {
    expect(
      parseAudarTranscript('  الحمد لله رب العالمين  '),
      'الحمد لله رب العالمين',
    );
  });
}
