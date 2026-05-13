// lib/shared/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const brand      = Color(0xFFF97316);
  static const brandLight = Color(0xFFFFF7ED);
  static const bg         = Color(0xFFFAF9F7);
  static const surface    = Color(0xFFFFFFFF);
  static const ink1       = Color(0xFF1A1A1A);
  static const ink2       = Color(0xFF6B7280);
  static const ink3       = Color(0xFF9CA3AF);
  static const border     = Color(0xFFE5E7EB);
  static const ok         = Color(0xFF10B981);
  static const err        = Color(0xFFEF4444);
  static const math       = Color(0xFF0EA5E9);
  static const eng        = Color(0xFF8B5CF6);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary:  AppColors.brand,
          surface:  AppColors.surface,
          error:    AppColors.err,
        ),
        scaffoldBackgroundColor: AppColors.bg,
        textTheme: GoogleFonts.interTextTheme(),
        cardTheme: CardThemeData(
          color:     AppColors.surface,
          elevation: 0,
          shape:     RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            minimumSize:     const Size(double.infinity, 52),
            shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            textStyle:       GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
            elevation:       0,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled:      true,
          fillColor:   AppColors.surface,
          border:      OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.brand, width: 2)),
          errorBorder:   OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.err)),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      );
}
