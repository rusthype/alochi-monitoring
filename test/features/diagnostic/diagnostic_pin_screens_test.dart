// School picker routes on `pin_required` (falling back to the legacy
// `kiosk_pin`); the PIN screen verifies through the server, not locally.
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_school_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_session_setup_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_widgets.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/l10n/app_localizations_ru.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pump(WidgetTester t, Widget home) async {
  SharedPreferences.setMockInitialValues({});
  final sp = await SharedPreferences.getInstance();
  t.view.physicalSize = const Size(1280, 720);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, __) => home),
    GoRoute(
        path: '/diagnostic_session_setup',
        builder: (_, __) => const Scaffold(body: Text('SETUP'))),
    GoRoute(
        path: '/diagnostic_class_select',
        builder: (_, __) => const Scaffold(body: Text('CLASSES'))),
  ]);
  await t.pumpWidget(ProviderScope(
    overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    child: MaterialApp.router(
      routerConfig: router,
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  group('school picker routing', () {
    Future<void> tapSchool(WidgetTester t, Map<String, dynamic> extra) async {
      await _pump(
          t,
          DiagnosticSchoolSelectScreen(
              loadSchools: () async => (
                    [
                      {
                        'school_id': 's1',
                        'school_name': 'A',
                        'school_number': 5,
                        ...extra,
                      }
                    ],
                    false
                  )));
      await t.tap(find.byType(DiagnosticPillButton));
      await t.pumpAndSettle();
    }

    testWidgets('pin_required true without kiosk_pin goes to the PIN screen',
        (t) async {
      await tapSchool(t, {'pin_required': true});
      expect(find.text('SETUP'), findsOneWidget);
    });

    testWidgets('pin_required false skips the PIN even with a kiosk_pin',
        (t) async {
      await tapSchool(t, {'pin_required': false, 'kiosk_pin': '1234'});
      expect(find.text('CLASSES'), findsOneWidget);
    });

    testWidgets('old backend: kiosk_pin decides', (t) async {
      await tapSchool(t, {'kiosk_pin': '1234'});
      expect(find.text('SETUP'), findsOneWidget);
    });

    testWidgets('old backend: empty kiosk_pin means no PIN', (t) async {
      await tapSchool(t, {'kiosk_pin': ''});
      expect(find.text('CLASSES'), findsOneWidget);
    });
  });

  group('PIN screen', () {
    final ru = AppLocalizationsRu();

    void ignoreOverflow() {
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        if (!d.exceptionAsString().contains('overflowed')) prev?.call(d);
      };
      addTearDown(() => FlutterError.onError = prev);
    }

    Future<void> submit(WidgetTester t, http.Response Function() respond,
        {String legacy = ''}) async {
      ignoreOverflow();
      await http.runWithClient(() async {
        await _pump(
            t,
            DiagnosticSessionSetupScreen(
                schoolId: 's1',
                schoolName: 'A',
                schoolCode: '5',
                expectedPin: legacy));
        await t.enterText(find.byType(TextField), '1234');
        await t.testTextInput.receiveAction(TextInputAction.done);
        await t.pump(const Duration(milliseconds: 600));
        await t.pump(const Duration(milliseconds: 600));
        await t.pumpAndSettle();
      }, () => MockClient((_) async => respond()));
    }

    testWidgets('server 403 shows the wrong-PIN text', (t) async {
      await submit(t, () => http.Response('{"detail":"x"}', 403));
      expect(find.text(ru.incorrectPin), findsOneWidget);
      expect(find.text('CLASSES'), findsNothing);
    });

    testWidgets('server 429 shows the throttled text', (t) async {
      await submit(t, () => http.Response('{"detail":"x"}', 429),
          legacy: '1234');
      expect(find.text(ru.tooManyAttempts), findsOneWidget);
      expect(find.text('CLASSES'), findsNothing);
    });

    testWidgets('route missing + matching list pin continues', (t) async {
      await submit(t, () => http.Response('<html>', 404), legacy: '1234');
      expect(find.text('CLASSES'), findsOneWidget);
    });

    testWidgets('route missing and no list pin shows a server error',
        (t) async {
      await submit(t, () => http.Response('<html>', 404));
      expect(find.text(ru.serverErrorRetry), findsOneWidget);
    });
  });
}
