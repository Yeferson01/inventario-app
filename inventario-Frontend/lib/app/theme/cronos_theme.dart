import 'package:flutter/material.dart';

import 'cronos_colors.dart';
import 'cronos_radius.dart';

class CronosTheme {
  const CronosTheme._();

  static ThemeData light() {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: CronosColors.primary,
      brightness: Brightness.light,
      primary: CronosColors.primary,
      secondary: CronosColors.secondary,
      surface: CronosColors.surface,
      error: CronosColors.danger,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: CronosColors.surfaceSoft,
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: CronosColors.textPrimary,
        titleTextStyle: TextStyle(
          color: CronosColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: CronosColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CronosRadius.lg),
          side: const BorderSide(color: CronosColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CronosRadius.md),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: const BorderSide(color: CronosColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CronosRadius.md),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CronosColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CronosRadius.md),
          borderSide: const BorderSide(color: CronosColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CronosRadius.md),
          borderSide: const BorderSide(color: CronosColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CronosRadius.md),
          borderSide: const BorderSide(
            color: CronosColors.primary,
            width: 1.4,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: CronosColors.divider,
        thickness: 1,
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(
          fontSize: 32,
          fontWeight: FontWeight.w900,
          color: CronosColors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 26,
          fontWeight: FontWeight.w800,
          color: CronosColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w800,
          color: CronosColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: CronosColors.textPrimary,
        ),
        titleSmall: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: CronosColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          color: CronosColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          color: CronosColors.textSecondary,
        ),
        bodySmall: TextStyle(
          fontSize: 12,
          color: CronosColors.textMuted,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: CronosColors.textMuted,
        ),
      ),
    );
  }
}
