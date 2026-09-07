import 'dart:math';

import 'package:aurisia_mobile/core/theme/app_theme.dart';
import 'package:aurisia_mobile/features/transcription/presentation/arabic_numbers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the application uses a light high-contrast reading theme', () {
    final theme = buildAurisiaTheme();

    expect(theme.brightness, Brightness.light);
    expect(theme.scaffoldBackgroundColor, AppColors.background);
    expect(
      _contrastRatio(AppColors.textPrimary, AppColors.background),
      greaterThanOrEqualTo(7),
    );
    expect(theme.textTheme.bodyLarge?.fontSize, greaterThanOrEqualTo(24));
  });

  test('speaker palette meets WCAG AA contrast on transcript cards', () {
    for (final color in SpeakerColors.palette) {
      final index = SpeakerColors.palette.indexOf(color);
      expect(
        _contrastRatio(color, SpeakerColors.cardBackgroundForIndex(index)),
        greaterThanOrEqualTo(4.5),
        reason: '$color must remain legible on its tinted card',
      );
    }
  });

  test('speaker labels use Arabic digits', () {
    expect(speakerDisplayName(0), 'المتحدث ١');
    expect(speakerDisplayName(11), 'المتحدث ١٢');
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = max(firstLuminance, secondLuminance);
  final darker = min(firstLuminance, secondLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}
