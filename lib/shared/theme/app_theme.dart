// lib/shared/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const brand      = Color(0xFFF97316);
  static const brandLight = Color(0xFFFFF7ED);
  static const bg         = Color(0xFFF8F8F6);
  static const surface    = Color(0xFFFFFFFF);
  static const ink1       = Color(0xFF1A1A1A);
  static const ink2       = Color(0xFF6B7280);
  static const ink3       = Color(0xFF9CA3AF);
  static const border     = Color(0xFFE5E7EB);
  static const ok         = Color(0xFF10B981);
  static const err        = Color(0xFFEF4444);
  static const math       = Color(0xFF0EA5E9);
  static const eng        = Color(0xFF8B5CF6);
  // Named shades
  static const gray50     = Color(0xFFF9FAFB);
  static const gray100    = Color(0xFFF3F4F6);
  static const gray200    = Color(0xFFE5E7EB);
  static const gray700    = Color(0xFF374151);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
        useMaterial3:            true,
        fontFamily:              GoogleFonts.inter().fontFamily,
        colorScheme: const ColorScheme.light(
          primary:    AppColors.brand,
          surface:    AppColors.surface,
          error:      AppColors.err,
        ),
        scaffoldBackgroundColor: AppColors.bg,
        textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
        cardTheme: CardThemeData(
          color:     AppColors.surface,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.border),
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.brand,
            foregroundColor: Colors.white,
            minimumSize:     const Size(double.infinity, 50),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            textStyle: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w700),
            elevation: 0,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled:      true,
          fillColor:   AppColors.gray50,
          border:      OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.brand, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.err),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.err, width: 2),
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
          labelStyle:     const TextStyle(color: AppColors.ink2, fontSize: 13),
          hintStyle:      const TextStyle(color: AppColors.ink3, fontSize: 14),
          errorStyle:     const TextStyle(color: AppColors.err, fontSize: 12),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.border, space: 0),
      );
}
