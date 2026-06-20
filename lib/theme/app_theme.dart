import 'package:flutter/material.dart';

class AppColors {
  static const primary = Color(0xFF1D5DA8);
  static const primaryDark = Color(0xFF0C2E68);
  static const accent = Color(0xFF2F86C9);
  static const ink = Color(0xFF142238);
  static const muted = Color(0xFF64748B);
  static const border = Color(0xFFD9E2EE);
  static const surface = Colors.white;
  static const background = Color(0xFFF5F7FA);
  static const chatBackground = Color(0xFFF0F4F8);
  static const bubbleMe = Color(0xFFE2EEFC);
  static const bubbleOther = Colors.white;
  static const student = Color(0xFF147A8A);
  static const teacher = Color(0xFF1D5DA8);
  static const admin = Color(0xFF9A5A12);
  static const danger = Color(0xFFB42318);
}

class AppTheme {
  static ThemeData get light {
    return ThemeData(
      colorSchemeSeed: AppColors.primary,
      useMaterial3: true,
      scaffoldBackgroundColor: AppColors.background,
      visualDensity: VisualDensity.standard,
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w800,
          letterSpacing: 0,
        ),
        titleMedium: TextStyle(
          color: AppColors.ink,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
        ),
        bodyMedium: TextStyle(color: AppColors.ink, letterSpacing: 0),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: AppColors.ink,
        surfaceTintColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        surfaceTintColor: AppColors.surface,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.border),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
      dividerTheme: const DividerThemeData(color: AppColors.border),
    );
  }
}
