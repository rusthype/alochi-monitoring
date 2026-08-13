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

  // ── Accent (auth / session flow) ───────────────────────────────────────────
  static const Color accent = Color(0xFFDE8E52);

  // ── Extended semantic colors (quiz / test flows) ───────────────────────────
  static const Color emerald       = Color(0xFF10B981);
  static const Color emeraldInk    = Color(0xFF065F46);
  static const Color emeraldMuted  = Color(0xFFECFDF5);
  static const Color mint          = Color(0xFF00D68F);

  static const Color violet       = Color(0xFF7C3AED);
  static const Color violetDark   = Color(0xFF5B21B6);
  static const Color violetInk    = Color(0xFF6D28D9);
  static const Color violetMuted  = Color(0xFFF5F3FF);
  static const Color violetBorder = Color(0xFFDDD6FE);

  static const Color blue       = Color(0xFF3B82F6);
  static const Color blueDark   = Color(0xFF1D4ED8);
  static const Color blueInk    = Color(0xFF1E40AF);
  static const Color blueMuted  = Color(0xFFEFF6FF);
  static const Color blueBorder = Color(0xFFBFDBFE);
  static const Color navyInk    = Color(0xFF1E3A5F);

  static const Color tealInk   = Color(0xFF0F766E);
  static const Color tealMuted = Color(0xFFF0FDFA);
  static const Color cyan      = Color(0xFF0891B2);

  static const Color amber       = Color(0xFFF59E0B);
  static const Color amberDark   = Color(0xFFD97706);
  static const Color amberInk    = Color(0xFF7C2D12);
  static const Color amberBorder = Color(0xFFFED7AA);

  static const Color brightRed   = Color(0xFFEF4444);
  static const Color dangerBorder = Color(0xFFFCA5A5);

  static const Color correctBorder = Color(0xFF86EFAC);
  static const Color correctInk    = Color(0xFF16A34A);

  static const Color gold  = Color(0xFFFBBF24);
  static const Color flame = Color(0xFFF97316);

  // ── Neutrals (chip / unselected states) ────────────────────────────────────
  static const Color chipBg          = Color(0xFFF4F4F5);
  static const Color chipBorder      = Color(0xFFD4D4D8);
  static const Color chipBorderMuted = Color(0xFFE4E4E7);
  static const Color chipIcon        = Color(0xFFA1A1AA);
  static const Color charcoal        = Color(0xFF111111);
  static const Color stone           = Color(0xFF737373);
  static const Color pageBg          = Color(0xFFFAFAFA);
  static const Color hoverBg         = Color(0xFFF5F5F5);
  static const Color slateDark       = Color(0xFF334155);

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

  // ── Dark theme tokens ──────────────────────────────────────────────────────
  // Adapted from the light palette above (same brand accent, inverted
  // surfaces/text) — used by AppTheme.darkTheme and by screens that opt in
  // to reading Theme.of(context).brightness directly (most existing screens
  // still use the static light AppColors constants above and do not yet
  // respond to dark mode — see student_settings_screen.dart file header).
  static const Color darkBg      = Color(0xFF121212);
  static const Color darkSurface = Color(0xFF1E1E1E);
  static const Color darkBorder  = Color(0xFF2C2C2C);
  static const Color darkInk1    = Color(0xFFFFFFFF);
  static const Color darkInk2    = Color(0xFF9CA3AF);
  static const Color darkInk3    = Color(0xFF71767F);
}
