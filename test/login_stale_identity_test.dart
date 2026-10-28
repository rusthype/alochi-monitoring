// Shared kiosk: opening the login screen drops the previous student's token /
// identity, and the form is NOT pre-filled with the previous student's cached
// credentials (pressing Login on it signed the next child in as the previous).
import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/models/models.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/features/auth/login_screen.dart';
import 'package:alochi_monitoring/features/session/session_providers.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Api extends MonitoringApi {
  int clears = 0;
  @override
  Future<bool> ping() async => true;
  @override
  void clearToken() {
    clears++;
    super.clearToken();
  }
}

void main() {
  late MonitoringApi savedApi;
  setUp(() => savedApi = api);
  tearDown(() => api = savedApi);

  testWidgets('stale token + session cleared; saved credentials not pre-filled',
      (tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      ConnectivityService.instance.dispose();
      tester.view.reset();
    });
    // A previous student's credentials sit in the secure store.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
            (call) async {
      if (call.method == 'read') {
        final key = (call.arguments as Map)['key'];
        if (key == 'cc_username') return 'previous.student';
        if (key == 'cc_password') return 'previous-secret';
      }
      return null;
    });
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final fake = _Api()..setToken('stale-token');
    api = fake;

    final container = ProviderContainer(overrides: [
      sharedPreferencesProvider.overrideWithValue(prefs),
    ]);
    addTearDown(container.dispose);
    container.read(currentStudentSessionProvider.notifier).state =
        const StudentSession(
            token: 'stale-token', studentId: 'S-1', studentName: 'Previous');

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.theme,
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const LoginScreen(),
      ),
    ));
    await tester.pump();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 400));

    expect(fake.clears, greaterThanOrEqualTo(1));
    expect(container.read(currentStudentSessionProvider), isNull);
    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    for (final f in fields) {
      expect(f.controller.text, isEmpty);
    }
    expect(find.text('previous.student'), findsNothing);

    ConnectivityService.instance.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
