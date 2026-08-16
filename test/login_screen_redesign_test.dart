import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/features/auth/login_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('first frame renders the 460px unified login card',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    addTearDown(() async {
      ConnectivityService.instance.dispose();
      tester.view.reset();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: AppTheme.theme,
          locale: const Locale('uz'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LoginScreen(),
        ),
      ),
    );

    final card = find.byKey(const ValueKey('login-unified-card'));
    expect(card, findsOneWidget);
    expect(tester.getSize(card).width, 460);
    expect(find.byKey(const ValueKey('login-tab-student')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-tab-proctor')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-tab-tests')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-form')), findsOneWidget);

    ConnectivityService.instance.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('proctor tab replaces the student form with the catalog panel',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    addTearDown(() {
      ConnectivityService.instance.dispose();
      tester.view.reset();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: AppTheme.theme,
          locale: const Locale('uz'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LoginScreen(),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('login-tab-proctor')));
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byKey(const ValueKey('proctor-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-form')), findsNothing);

    ConnectivityService.instance.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('dark Russian layout remains stable at the compact viewport',
      (tester) async {
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    addTearDown(() {
      ConnectivityService.instance.dispose();
      tester.view.reset();
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPreferencesProvider.overrideWithValue(prefs),
        ],
        child: MaterialApp(
          theme: AppTheme.theme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.dark,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pump();

    final card = find.byKey(const ValueKey('login-unified-card'));
    expect(tester.getSize(card).width, 460);
    expect(find.text('Мониторинг Alochi'), findsOneWidget);
    expect(tester.takeException(), isNull);

    ConnectivityService.instance.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
