import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/transcript_segment.dart';
import 'arabic_numbers.dart';

class SpeakerTranscriptCard extends StatelessWidget {
  const SpeakerTranscriptCard({required this.segment, super.key});

  final TranscriptSegment segment;

  @override
  Widget build(BuildContext context) {
    final speakerColor = SpeakerColors.forIndex(segment.speakerIndex);
    final speakerName = speakerDisplayName(segment.speakerIndex);

    return Semantics(
      label: '$speakerName، ${segment.displayText}',
      child: Container(
        key: ValueKey(segment.eventId),
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: SpeakerColors.cardBackgroundForIndex(segment.speakerIndex),
          borderRadius: BorderRadius.circular(20),
          border: Border(right: BorderSide(color: speakerColor, width: 6)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x16000000),
              blurRadius: 10,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SpeakerAvatar(index: segment.speakerIndex, color: speakerColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    speakerName,
                    key: ValueKey('speaker-${segment.speakerIndex}'),
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(color: speakerColor),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    segment.displayText,
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: segment.isFinal
                          ? AppColors.textPrimary
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeakerAvatar extends StatelessWidget {
  const _SpeakerAvatar({required this.index, required this.color});

  final int index;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 50,
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.1),
        border: Border.all(color: color, width: 3),
      ),
      child: Text(
        toArabicDigits(index + 1),
        style: TextStyle(
          color: color,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
