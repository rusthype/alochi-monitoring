// lib/core/theme/app_prefs_provider.dart
//
// Local, device-only display/notification preferences for the student
// cabinet — same shared_preferences-backed Notifier pattern as
// core/locale/locale_provider.dart's LocaleNotifier. No server sync: these
// never leave the device, matching how localeProvider itself already works.
//
// themeModeProvider + fontScaleProvider are wired at the MaterialApp root
// (main.dart) so the toggle in student_settings_screen.dart takes effect
// live app-wide for anything reading Theme.of(context)/MediaQuery — but most
// existing screens paint from the static light AppColors/AppTextStyles
// constants directly rather than Theme.of(context), so they won't visually
// react to themeModeProvider yet. See student_settings_screen.dart's header
// for the documented scope of what actually repaints today.
//
// soundOnCompleteProvider / testReminderProvider persist real toggles, but
// this kiosk app has no completion-sound playback and no local/push
// reminder system to gate — nothing reads them yet (see settings screen
// header). They are not fake UI: the value genuinely persists and could
// gate a future feature, it's just that no such feature exists today.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../locale/locale_provider.dart' show sharedPreferencesProvider;

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  static const _key = 'app_theme_mode';

  @override
  ThemeMode build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getString(_key) == 'dark' ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> setDark(bool dark) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_key, dark ? 'dark' : 'light');
    state = dark ? ThemeMode.dark : ThemeMode.light;
  }
}

/// MediaQuery text-scale override — two-state only (matches the mockup's
/// Обычный/Крупный toggle), not a free slider.
final fontScaleProvider =
    NotifierProvider<FontScaleNotifier, double>(FontScaleNotifier.new);

class FontScaleNotifier extends Notifier<double> {
  static const _key = 'app_font_scale_large';
  static const normal = 1.0;
  static const large = 1.15;

  @override
  double build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return (prefs.getBool(_key) ?? false) ? large : normal;
  }

  Future<void> setLarge(bool isLarge) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_key, isLarge);
    state = isLarge ? large : normal;
  }
}

class BoolPrefNotifier extends Notifier<bool> {
  final String _key;
  final bool _defaultValue;
  BoolPrefNotifier(this._key, {required bool defaultValue})
      : _defaultValue = defaultValue;

  @override
  bool build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    return prefs.getBool(_key) ?? _defaultValue;
  }

  Future<void> set(bool value) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setBool(_key, value);
    state = value;
  }
}

final soundOnCompleteProvider = NotifierProvider<BoolPrefNotifier, bool>(
  () => BoolPrefNotifier('pref_sound_on_complete', defaultValue: true),
);

final testReminderProvider = NotifierProvider<BoolPrefNotifier, bool>(
  () => BoolPrefNotifier('pref_test_reminders', defaultValue: true),
);
