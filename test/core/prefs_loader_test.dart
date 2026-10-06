import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/storage/prefs_loader.dart';
import 'package:alochi_monitoring/core/theme/app_prefs_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('broken prefs -> in-memory fallback; locale/theme providers still work',
      () async {
    var calls = 0;
    final errors = <Object>[];
    final prefs = await loadPrefsWithFallback(
      load: () async {
        calls++;
        throw const FormatException('corrupt shared_preferences.json');
      },
      retryDelay: Duration.zero,
      onFailure: (e, _) => errors.add(e),
    );

    expect(calls, 2); // retried once
    expect(errors, hasLength(2));

    // Same wiring as main(): the provider is always overridden.
    final container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
    );
    addTearDown(container.dispose);

    expect(container.read(localeProvider), const Locale('uz'));
    expect(container.read(themeModeProvider), ThemeMode.light);
    await container.read(localeProvider.notifier).setLocale(const Locale('ru'));
    expect(container.read(localeProvider), const Locale('ru'));

    // Direct SharedPreferences.getInstance() callers get a working store too.
    expect(await SharedPreferences.getInstance(), isNotNull);
  });

  test('transient failure succeeds on retry without fallback', () async {
    SharedPreferences.setMockInitialValues({'app_locale': 'en'});
    var calls = 0;
    final prefs = await loadPrefsWithFallback(
      load: () async {
        if (calls++ == 0) throw StateError('locked');
        return SharedPreferences.getInstance();
      },
      retryDelay: Duration.zero,
    );
    expect(prefs.getString('app_locale'), 'en');
  });
}
