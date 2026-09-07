import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class AppColors {
  static const background = Color(0xFFF4F7F5);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceElevated = Color(0xFFE8EFEC);
  static const primary = Color(0xFF006B4F);
  static const textPrimary = Color(0xFF11181A);
  static const textSecondary = Color(0xFF4B5960);
  static const outline = Color(0xFFC8D1CE);
  static const error = Color(0xFFB3261E);
  static const onAccent = Color(0xFFFFFFFF);
}

abstract final class SpeakerColors {
  // Every color has at least 4.5:1 contrast against AppColors.surface.
  static const palette = <Color>[
    Color(0xFF7A4A00),
    Color(0xFF005C8A),
    Color(0xFF8E2858),
    Color(0xFF2E6A35),
    Color(0xFF60429B),
    Color(0xFF984000),
  ];

  static Color forIndex(int index) {
    if (index < 0) {
      throw ArgumentError.value(index, 'index', 'must not be negative');
    }
    return palette[index % palette.length];
  }

  static Color cardBackgroundForIndex(int index) {
    return Color.alphaBlend(
      forIndex(index).withValues(alpha: 0.055),
      AppColors.surface,
    );
  }
}

ThemeData buildAurisiaTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.primary,
    brightness: Brightness.light,
    surface: AppColors.surface,
    error: AppColors.error,
  );

  return ThemeData(
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    useMaterial3: true,
    iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 28),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(minimumSize: const Size(52, 52)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(72, 72),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
      ),
    ),
    textTheme: const TextTheme(
      headlineSmall: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 28,
        fontWeight: FontWeight.w800,
        height: 1.35,
      ),
      titleMedium: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w700,
        height: 1.4,
      ),
      bodyLarge: TextStyle(
        color: AppColors.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w600,
        height: 1.6,
      ),
      bodyMedium: TextStyle(
        color: AppColors.textSecondary,
        fontSize: 16,
        height: 1.5,
      ),
    ),
  );
}

class AurisiaSystemUi extends StatelessWidget {
  const AurisiaSystemUi({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.dark.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: AppColors.surface,
        systemNavigationBarDividerColor: AppColors.outline,
      ),
      child: child,
    );
  }
}
