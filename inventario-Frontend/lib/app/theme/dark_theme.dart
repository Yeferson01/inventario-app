import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'colors.dart';
import 'typography.dart';

class AppDarkTheme {
  AppDarkTheme._();

  static ThemeData get theme {
    return FlexThemeData.dark(
      // En v8 los colores se definen directamente usando los parámetros individuales
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.dark,
        primary: const Color(0xFF94A3B8),
        secondary: AppColors.secondary,
        error: const Color(0xFFCF6679),
      ),
      textTheme: AppTypography.getTextTheme(),
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 20,
        buttonPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),
    );
  }
}