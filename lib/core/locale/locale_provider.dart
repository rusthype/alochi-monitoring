import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Provides the synchronously loaded SharedPreferences instance.
// Must be overridden in ProviderScope at startup.
final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('sharedPreferencesProvider must be overridden');
});

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(() {
  return LocaleNotifier();
});

class LocaleNotifier extends Notifier<Locale> {
  static const _localeKey = 'app_locale';

  @override
  Locale build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final savedLocale = prefs.getString(_localeKey);
    if (savedLocale != null) {
      return Locale(savedLocale);
    }
    return const Locale('uz'); // Default to Uzbek
  }

  Future<void> setLocale(Locale locale) async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setString(_localeKey, locale.languageCode);
    state = locale;
  }
}
