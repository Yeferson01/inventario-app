import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';
import 'colors.dart';
import 'typography.dart';

class AppLightTheme {
  AppLightTheme._();

  static ThemeData get theme {
    return FlexThemeData.light(
      // En v8 los colores se definen directamente usando los parámetros individuales
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        primary: AppColors.primary,
        secondary: AppColors.secondary,
        error: const Color(0xFFB00020),
      ),
      appBarBackground: AppColors.primary,
      textTheme: AppTypography.getTextTheme(),
      subThemesData: const FlexSubThemesData(
        blendOnLevel: 10,
        buttonPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        unselectedToggleIsColored: true,
      ),
    );
  }
}