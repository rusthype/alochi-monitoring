import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/auth/school_pick_screen.dart';
import 'package:alochi_monitoring/features/session/session_providers.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

CatalogEntry entry(String key, List<SchoolButton> buttons) => CatalogEntry(
      testKey: key,
      title: key,
      grade: 1,
      version: 1,
      status: CatalogStatus.notDownloaded,
      schoolButtons: buttons,
    );

SchoolButton btn(String code, String id) => SchoolButton(
      pin: '',
      label: '$code-maktab',
      schoolCode: code,
      schoolId: id,
      randomVariant: false,
    );

void main() {
  late ProviderContainer container;
  Object? setupExtra;

  Future<void> pump(
    WidgetTester t,
    Future<MonitoringSchoolSources> Function() load, {
    Map<String, Object> prefs = const {},
  }) async {
    SharedPreferences.setMockInitialValues(prefs);
    final sp = await SharedPreferences.getInstance();
    t.view.physicalSize = const Size(1280, 720);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    setupExtra = null;
    container = ProviderContainer(
      overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
    );
    addTearDown(container.dispose);
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (_, __) => const Text('LOGIN')),
        GoRoute(
          path: '/school_select',
          builder: (_, __) => SchoolPickScreen(load: load),
        ),
        GoRoute(
          path: '/session_setup',
          builder: (_, s) {
            setupExtra = s.extra;
            return const Text('SETUP');
          },
        ),
      ],
    );
    await t.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(
          locale: const Locale('uz'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    router.push('/school_select');
    await t.pumpAndSettle();
  }

  MonitoringSchoolSources sources(
    List<CatalogEntry> e, [
    List<Map<String, String>> s = const [],
  ]) =>
      (entries: e, schools: s);

  testWidgets('renders schools; search filters', (t) async {
    await pump(
      t,
      () async => sources(
        [
          entry('t1', [btn('26', 'u26'), btn('5', 'u5')]),
        ],
        [
          {'school_code': '12', 'school_id': 'u12', 'label': '12-maktab'},
        ],
      ),
    );
    expect(find.text('5-maktab'), findsOneWidget);
    expect(find.text('12-maktab'), findsOneWidget);
    expect(find.text('26-maktab'), findsOneWidget);
    await t.enterText(find.byType(TextField), '12');
    await t.pumpAndSettle();
    expect(find.text('12-maktab'), findsOneWidget);
    expect(find.text('5-maktab'), findsNothing);
  });

  testWidgets('tap sets providers and pushes /session_setup (stays below)',
      (t) async {
    final e = entry('t1', [btn('26', 'u26')]);
    await pump(t, () async => sources([e]));
    await t.tap(find.text('26-maktab'));
    await t.pumpAndSettle();
    expect(find.text('SETUP'), findsOneWidget);
    expect(setupExtra, {'testKey': 't1'});
    expect(container.read(selectedCatalogEntryProvider), same(e));
    expect(container.read(selectedSchoolCodeProvider), '26');
    // Picker is still underneath: back returns to it, not to login.
    final r = GoRouter.of(t.element(find.text('SETUP')));
    r.pop();
    await t.pumpAndSettle();
    expect(find.byType(SchoolPickScreen), findsOneWidget);
    expect(
        (await SharedPreferences.getInstance())
            .getString(kLastMonitoringSchoolKey),
        'u26');
  });

  testWidgets('school known only from the live list gets a fallback entry',
      (t) async {
    await pump(
      t,
      () async => sources([], [
        {'school_code': '7', 'school_id': 'u7', 'label': '7-maktab'},
      ]),
    );
    await t.tap(find.text('7-maktab'));
    await t.pumpAndSettle();
    expect(setupExtra, {'testKey': ''});
    final sel = container.read(selectedCatalogEntryProvider)!;
    expect(sel.testKey, '');
    expect(sel.schoolButtons.single.schoolCode, '7');
    expect(sel.schoolButtons.single.schoolId, 'u7');
    expect(container.read(selectedSchoolCodeProvider), '7');
  });

  testWidgets('last chosen school is pinned with marker', (t) async {
    await pump(
      t,
      () async => sources([
        entry('t', [btn('1', 'u1'), btn('2', 'u2'), btn('3', 'u3')]),
      ]),
      prefs: {kLastMonitoringSchoolKey: 'u3'},
    );
    expect(find.text('Oxirgi tanlangan'), findsOneWidget);
    expect(
      t.getTopLeft(find.text('3-maktab')).dy,
      lessThan(t.getTopLeft(find.text('1-maktab')).dy),
    );
  });

  testWidgets('empty state', (t) async {
    await pump(t, () async => sources([]));
    expect(find.text('Testlar topilmadi'), findsOneWidget);
  });

  testWidgets('error state with retry', (t) async {
    var calls = 0;
    await pump(t, () async {
      if (calls++ == 0) throw Exception('boom');
      return sources([
        entry('t', [btn('4', 'u4')]),
      ]);
    });
    expect(find.textContaining('boom'), findsOneWidget);
    await t.tap(find.text('Qayta urinish'));
    await t.pumpAndSettle();
    expect(find.text('4-maktab'), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);
  });

  testWidgets('Esc closes the screen, also with the search field focused',
      (t) async {
    await pump(
      t,
      () async => sources([
        entry('t', [btn('1', 'u1'), btn('2', 'u2')]),
      ]),
    );
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.escape);
    await t.pumpAndSettle();
    expect(find.byType(SchoolPickScreen), findsNothing);
    expect(find.text('LOGIN'), findsOneWidget);
  });
}
