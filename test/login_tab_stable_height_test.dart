// Switching login tabs must never resize or move the unified card, the logo
// or the tab bar - only the panel content cross-fades inside a fixed area.
import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/features/auth/login_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ReachableApi extends MonitoringApi {
  @override
  Future<bool> ping() async => true;
}

void main() {
  late MonitoringApi savedApi;
  setUp(() {
    savedApi = api;
    api = _ReachableApi();
  });
  tearDown(() => api = savedApi);

  Future<void> pumpLogin(WidgetTester tester, {double textScale = 1}) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    addTearDown(ConnectivityService.instance.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          theme: AppTheme.theme,
          locale: const Locale('ru'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));
  }

  final cardKey = find.byKey(const ValueKey('login-unified-card'));
  final studentTab = find.byKey(const ValueKey('login-tab-student'));
  final diagTab = find.byKey(const ValueKey('login-tab-diagnostic'));
  final testsTab = find.byKey(const ValueKey('login-tab-tests'));

  for (final scale in [1.0, 1.3]) {
    testWidgets('card and tab bar keep their rect across tab switches '
        '(text scale $scale)', (tester) async {
      await pumpLogin(tester, textScale: scale);

      final card0 = tester.getRect(cardKey);
      final student0 = tester.getRect(studentTab);
      final diag0 = tester.getRect(diagTab);
      final tests0 = tester.getRect(testsTab);

      Future<void> expectStable(String step) async {
        expect(tester.getRect(cardKey), card0, reason: '$step: card');
        expect(tester.getRect(studentTab), student0, reason: '$step: tab 0');
        expect(tester.getRect(diagTab), diag0, reason: '$step: tab 1');
        expect(tester.getRect(testsTab), tests0, reason: '$step: tab 2');
      }

      Future<void> switchTo(Finder tab, String name) async {
        await tester.tap(tab);
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await expectStable('$name frame $i');
        }
      }

      await switchTo(diagTab, 'Ученик -> Диагностика');
      expect(find.byKey(const ValueKey('diagnostic-panel')), findsOneWidget);
      await switchTo(testsTab, 'Тесты (disabled, no-op)');
      await switchTo(studentTab, 'Диагностика -> Ученик');
      expect(find.byKey(const ValueKey('login-form')), findsOneWidget);
      expect(find.byKey(const ValueKey('diagnostic-panel')), findsNothing);
    });

    testWidgets('card is sized by the student form, diagnostic panel fits it '
        '(text scale $scale)', (tester) async {
      await pumpLogin(tester, textScale: scale);
      final formH =
          tester.getSize(find.byKey(const ValueKey('login-form'))).height;
      final studentCardH = tester.getSize(cardKey).height;
      // ignore: avoid_print
      print('scale $scale: student card=$studentCardH form=$formH');

      await tester.tap(diagTab);
      await tester.pump(const Duration(milliseconds: 400));
      final diagPanel = find.byKey(const ValueKey('diagnostic-panel'));
      expect(diagPanel, findsOneWidget);
      final diagCardH = tester.getSize(cardKey).height;
      final panelH = tester.getSize(diagPanel).height;
      // ignore: avoid_print
      print('scale $scale: diagnostic card=$diagCardH panel=$panelH');

      expect(diagCardH, studentCardH);
      expect(diagCardH, lessThanOrEqualTo(studentCardH)); // never taller
      expect(panelH, formH);
      expect(tester.takeException(), isNull);
    });
  }
}
