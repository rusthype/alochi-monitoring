import 'package:flutter/material.dart';

class AppColors {
  // ── Core palette ───────────────────────────────────────────────────────────
  static const Color primary   = Color(0xFF4F46E5);
  static const Color secondary = Color(0xFFE8954E);
  static const Color success   = Color(0xFF0F9A6E);
  static const Color error     = Color(0xFFDC2626);

  // ── Muted variants ─────────────────────────────────────────────────────────
  static const Color primaryMuted   = Color(0xFFEEF2FF);
  static const Color secondaryMuted = Color(0xFFFFF7ED);
  static const Color successMuted   = Color(0xFFF0FDF4);
  static const Color errorMuted     = Color(0xFFFEF2F2);

  // ── Backgrounds ────────────────────────────────────────────────────────────
  static const Color bg      = Color(0xFFF8F8F6);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color muted   = Color(0xFFF1F5F9);

  // ── Text ───────────────────────────────────────────────────────────────────
  static const Color ink1 = Color(0xFF1A1A1A);
  static const Color ink2 = Color(0xFF6B7280);
  static const Color ink3 = Color(0xFF9CA3AF);

  // ── Borders ────────────────────────────────────────────────────────────────
  static const Color border = Color(0xFFE5E7EB);

  // ── Subject colors ─────────────────────────────────────────────────────────
  static const Color vocab = secondary;
  static const Color eng   = Color(0xFF8B5CF6);
  static const Color math  = Color(0xFF0EA5E9);

  // ── Gray scale ─────────────────────────────────────────────────────────────
  static const Color gray50  = Color(0xFFF9FAFB);
  static const Color gray100 = Color(0xFFF3F4F6);
  static const Color gray200 = Color(0xFFE5E7EB);
  static const Color gray700 = Color(0xFF374151);

  // ── Backward-compat aliases ────────────────────────────────────────────────
  static const Color brand       = secondary;
  static const Color brandLight  = secondaryMuted;
  static const Color ok          = success;
  static const Color err         = error;
  static const Color okMuted     = successMuted;
  static const Color errMuted    = errorMuted;
  static const Color warnMuted   = Color(0xFFFFFBEB);

  // ── Semantic aliases ───────────────────────────────────────────────────────
  static const Color textPrimary   = ink1;
  static const Color textSecondary = ink2;
  static const Color textMuted     = ink3;
  static const Color background    = bg;
}
