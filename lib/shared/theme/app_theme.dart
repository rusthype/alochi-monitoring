// lib/shared/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Brand + section colors (light va dark mode uchun bir xil)
class AppColors {
  // Brand
  static const brand      = Color(0xFFF97316);
  static const brandLight = Color(0xFFFFF7ED);

  // Section colors
  static const vocab      = Color(0xFFF97316); // orange
  static const eng        = Color(0xFF2563EB); // blue
  static const math       = Color(0xFF7C3AED); // purple
  static const ok         = Color(0xFF16A34A); // green
  static const err        = Color(0xFFDC2626); // red

  // ── Light mode ──
  static const lightBg      = Color(0xFFF0EDE8);
  static const lightBg2     = Color(0xFFE8E4DE);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurf2   = Color(0xFFF7F5F2);
  static const lightBorder  = Color(0xFFDDD9D2);
  static const lightBorder2 = Color(0xFFCCC8C0);
  static const lightInk1    = Color(0xFF1A1814);
  static const lightInk2    = Color(0xFF4A4540);
  static const lightInk3    = Color(0xFF9A9690);

  // ── Dark mode ──
  static const darkBg       = Color(0xFF0D0D12);
  static const darkBg2      = Color(0xFF13131A);
  static const darkSurface  = Color(0xFF18181F);
  static const darkSurf2    = Color(0xFF1F1F28);
  static const darkBorder   = Color(0xFF2A2A38);
  static const darkBorder2  = Color(0xFF363648);
  static const darkInk1     = Color(0xFFF2F0EC);
  static const darkInk2     = Color(0xFF9A97A0);
  static const darkInk3     = Color(0xFF5A5868);

  // Legacy aliases (eski kod uchun)
  static const bg      = lightBg;
  static const surface = lightSurface;
  static const ink1    = lightInk1;
  static const ink2    = lightInk2;
  static const ink3    = lightInk3;
  static const border  = lightBorder;
  static const gray50  = Color(0xFFF9FAFB);
  static const gray100 = Color(0xFFF3F4F6);
  static const gray200 = Color(0xFFE5E7EB);
  static const gray700 = Color(0xFF374151);
}

class AppTheme {
  // ── Light theme ──
  static ThemeData get theme => _buildTheme(Brightness.light);

  // ── Dark theme ──
  static ThemeData get darkTheme => _buildTheme(Brightness.dark);

  static ThemeData _buildTheme(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bg      = isDark ? AppColors.darkBg      : AppColors.lightBg;
    final surface = isDark ? AppColors.darkSurface  : AppColors.lightSurface;
    final border  = isDark ? AppColors.darkBorder   : AppColors.lightBorder;
    final ink2    = isDark ? AppColors.darkInk2     : AppColors.lightInk2;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      fontFamily: GoogleFonts.outfit().fontFamily,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary:    AppColors.brand,
        onPrimary:  Colors.white,
        secondary:  AppColors.vocab,
        onSecondary: Colors.white,
        error:      AppColors.err,
        onError:    Colors.white,
        surface:    surface,
        onSurface:  isDark ? AppColors.darkInk1 : AppColors.lightInk1,
        surfaceContainerHighest: isDark ? AppColors.darkSurf2 : AppColors.lightSurf2,
      ),
      scaffoldBackgroundColor: bg,
      textTheme: GoogleFonts.outfitTextTheme(
        isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        shadowColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 50),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13)),
          textStyle: GoogleFonts.outfit(
              fontSize: 15, fontWeight: FontWeight.w700),
          elevation: 0,
          shadowColor: Colors.transparent,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor:
            isDark ? AppColors.darkBg2 : AppColors.lightBg2,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.brand, width: 1.5),
        ),
        labelStyle: TextStyle(color: ink2),
        hintStyle: TextStyle(
            color: isDark ? AppColors.darkInk3 : AppColors.lightInk3),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1),
    );
  }
}

/// ThemeMode ni SharedPreferences da saqlash uchun provider
class ThemeNotifier extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }

  void setMode(ThemeMode m) {
    _mode = m;
    notifyListeners();
  }
}
