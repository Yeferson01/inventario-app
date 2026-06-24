import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class AppTypography {
  AppTypography._();

  static TextStyle get displayLarge => TextStyle(
      fontSize: 57.sp, fontWeight: FontWeight.bold, letterSpacing: -0.25);
  // Cambiado FontWeight.semibold por FontWeight.w600
  static TextStyle get headlineLarge =>
      TextStyle(fontSize: 32.sp, fontWeight: FontWeight.w600);
  static TextStyle get titleLarge =>
      TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w500);
  static TextStyle get bodyLarge =>
      TextStyle(fontSize: 16.sp, fontWeight: FontWeight.normal);
  static TextStyle get labelLarge =>
      TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500);

  static TextTheme getTextTheme() {
    return TextTheme(
      displayLarge: displayLarge,
      headlineLarge: headlineLarge,
      titleLarge: titleLarge,
      bodyLarge: bodyLarge,
      labelLarge: labelLarge,
    );
  }
}
