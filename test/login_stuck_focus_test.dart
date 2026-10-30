import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/features/auth/login_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/theme/app_theme.dart';
import 'package:alochi_monitoring/shared/widgets/button_shape.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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

  test('pointerOnlyOverlay paints hover/press but never focus', () {
    final overlay = pointerOnlyOverlay(Colors.black);
    expect(overlay.resolve({WidgetState.hovered}), isNotNull);
    expect(overlay.resolve({WidgetState.pressed}), isNotNull);
    expect(overlay.resolve({WidgetState.focused}), isNull);
    expect(overlay.resolve({WidgetState.focused, WidgetState.hovered}),
        isNotNull);
    expect(bottomChipButtonStyle(foreground: Colors.black)
        .overlayColor!
        .resolve({WidgetState.focused}), isNull);
  });

  testWidgets('login tab shows no focus highlight after push + pop',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    addTearDown(() {
      ConnectivityService.instance.dispose();
      tester.view.reset();
    });
    // Desktop keyboard/mouse: focus highlights are in "traditional" mode.
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(() =>
        FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic);

    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/history',
          builder: (_, __) => const Scaffold(body: Text('other'))),
    ]);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp.router(
          routerConfig: router,
          theme: AppTheme.theme,
          locale: const Locale('uz'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    );

    final tab = find.byKey(const ValueKey('login-tab-diagnostic'));
    await tester.tap(tab);
    await tester.pump(const Duration(milliseconds: 400));
    // Focus on the tab, as restored by the route's FocusScope on pop.
    Focus.of(tester.element(find.descendant(
            of: tab, matching: find.byType(Padding)).first))
        .requestFocus();
    router.push('/history');
    await tester.pump(const Duration(milliseconds: 600));
    router.pop();
    await tester.pump(const Duration(milliseconds: 600));

    // The focus highlight is still "alive" (keyboard focus works) but its
    // colour is transparent, so nothing is painted on the idle tab.
    expect(tester.widget<InkWell>(tab).focusColor, Colors.transparent);
  });
}
