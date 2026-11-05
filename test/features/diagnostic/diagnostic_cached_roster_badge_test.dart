// End-to-end wiring of the cached-roster notice: a real DiagnosticKioskApi
// (mock HTTP client + the real DiagnosticKioskCache) feeds the real school /
// class / student pickers, which must show
//   429 / 5xx with a cached list -> "server busy, showing saved list"
//   status 0 (offline)           -> the offline wording
//   live success                 -> no badge at all
// Real cache IO needs tester.runAsync (FakeAsync would hang on it): the cache
// is seeded and the AES key warmed there, then the pickers run under FakeAsync.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/diagnostic_kiosk_cache.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_class_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_school_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_student_select_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_widgets.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/l10n/app_localizations_uz.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _uz = AppLocalizationsUz();
const _school = 's1';

const _schoolsLive = [
  {
    'school_id': _school,
    'school_name': 'Jonli maktab',
    'school_number': 27,
    'kiosk_pin': '',
  }
];
const _schoolsCached = [
  {
    'school_id': _school,
    'school_name': 'Saqlangan maktab',
    'school_number': 26,
    'kiosk_pin': '',
  }
];
const _classesLive = [
  {'class_label': '4-A', 'language': 'uz'}
];
const _classesCached = [
  {'class_label': '5-B', 'language': 'uz'}
];
const _studentsLive = [
  {'attempt_id': 'a1', 'student_name': 'Jonli Ali', 'session_grade': 4}
];
const _studentsCached = [
  {'attempt_id': 'a2', 'student_name': 'Saqlangan Vali', 'session_grade': 4}
];

/// What the mock server does for the picker's list request.
enum _Net { s429, s500, offline, live }

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DiagnosticKioskApi savedApi;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => call.method == 'getApplicationSupportDirectory'
                ? Directory.systemTemp.path
                : null);
    savedApi = diagnosticKioskApi;
    diagnosticKioskApi = DiagnosticKioskApi(); // fresh lastFallbackWasOffline
  });
  tearDown(() => diagnosticKioskApi = savedApi);

  http.Client server(_Net net, Object liveBody) => MockClient((_) async {
        switch (net) {
          case _Net.s429:
            return http.Response('{}', 429);
          case _Net.s500:
            return http.Response('{}', 500);
          case _Net.offline:
            throw const SocketException('down');
          case _Net.live:
            return http.Response(jsonEncode(liveBody), 200);
        }
      });

  /// Seeds the cache (and warms the AES key) with real IO, then pumps
  /// [screen] with every kiosk HTTP call answered by [client].
  Future<void> pump(WidgetTester t, Widget screen, http.Client client,
      {required String cacheKey, required Object cached}) async {
    await t.runAsync(() => DiagnosticKioskCache.save(cacheKey, cached));
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await http.runWithClient(() async {
      await t.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
        child: MaterialApp(
          locale: const Locale('uz'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: screen,
        ),
      ));
      // The cache read hops through real async IO that FakeAsync cannot run:
      // alternate real time (runAsync) with fake time (pump) until it lands.
      for (var i = 0; i < 20; i++) {
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 25)));
        await t.pump(const Duration(seconds: 1));
      }
      await t.pumpAndSettle();
    }, () => client);
  }

  /// Badge expectation shared by the three pickers.
  void expectBadge(_Net net) {
    switch (net) {
      case _Net.s429:
      case _Net.s500:
        expect(find.byType(DiagnosticOfflineBadge), findsOneWidget);
        expect(find.text(_uz.diagnosticServerBusyCached), findsOneWidget);
        expect(find.text(_uz.diagnosticOfflineCached), findsNothing);
      case _Net.offline:
        expect(find.byType(DiagnosticOfflineBadge), findsOneWidget);
        expect(find.text(_uz.diagnosticOfflineCached), findsOneWidget);
        expect(find.text(_uz.diagnosticServerBusyCached), findsNothing);
      case _Net.live:
        expect(find.byType(DiagnosticOfflineBadge), findsNothing);
        expect(find.text(_uz.diagnosticOfflineCached), findsNothing);
        expect(find.text(_uz.diagnosticServerBusyCached), findsNothing);
    }
  }

  test('the three wordings are different', () {
    expect(_uz.diagnosticServerBusyCached, isNot(_uz.diagnosticOfflineCached));
  });

  group('school picker', () {
    for (final net in _Net.values) {
      testWidgets('$net', (t) async {
        await pump(
            t, const DiagnosticSchoolSelectScreen(), server(net, _schoolsLive),
            cacheKey: 'schools', cached: _schoolsCached);
        expectBadge(net);
        // Rows come from the cache unless the live call worked.
        expect(
            find.textContaining(net == _Net.live ? '27' : '26'), findsWidgets);
        expect(
            find.textContaining(net == _Net.live ? '26' : '27'), findsNothing);
      });
    }
  });

  group('class picker', () {
    for (final net in _Net.values) {
      testWidgets('$net', (t) async {
        await pump(
            t,
            const DiagnosticClassSelectScreen(
                schoolId: _school, schoolName: 'Maktab'),
            server(net, _classesLive),
            cacheKey: 'classes_$_school',
            cached: _classesCached);
        expectBadge(net);
        expect(find.text(net == _Net.live ? '4-A' : '5-B'), findsWidgets);
      });
    }
  });

  group('student picker', () {
    for (final net in _Net.values) {
      testWidgets('$net', (t) async {
        await pump(
            t,
            DiagnosticStudentSelectScreen(
              schoolId: _school,
              schoolName: 'Maktab',
              classLabel: '4-A',
              language: 'uz',
              connectivityStreamOverride: const Stream.empty(),
              availableSubjectsOverride: (grade,
                      {String language = 'uz'}) async =>
                  {'subjects': <String>[]},
              peekSubjectOverride: (
                      {required attemptId, required subject}) async =>
                  {'fixed_variant': false},
            ),
            server(net, _studentsLive),
            cacheKey: 'students_${_school}_4-A_uz',
            cached: _studentsCached);
        expectBadge(net);
        expect(find.text(net == _Net.live ? 'Jonli Ali' : 'Saqlangan Vali'),
            findsWidgets);
      });
    }
  });
}
