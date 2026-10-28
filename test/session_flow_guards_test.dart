// Proctor session flow (school pick -> setup -> group select): load failures
// show a localized retry banner (never raw exception text, never "not found"),
// double taps do not stack routes, stale group answers are ignored, newer test
// versions are re-downloaded before the roster opens, and a school without
// groups still reaches the roster through the router.
import 'dart:async';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/router/app_router.dart';
import 'package:alochi_monitoring/core/services/groups_cache.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/session/group_select_screen.dart';
import 'package:alochi_monitoring/features/session/session_providers.dart';
import 'package:alochi_monitoring/features/session/session_setup_screen.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers/app_harness.dart';

Map<String, dynamic> _playable(int version) => {
      'title': 'T',
      'grade': 5,
      'version': version,
      'parts': ['Math'],
      'variants': {
        '1': {
          'Math': [
            {
              'type': 'text_choice',
              'q': 'x',
              'opts': ['a', 'b'],
              'ans': 0
            }
          ]
        }
      },
    };

Map<String, dynamic> _item(String key, String title, {int version = 1}) =>
    {'test_key': key, 'title': title, 'grade': 5, 'version': version};

class _Api extends MonitoringApi {
  Object? groupsError;
  List<Map<String, dynamic>> groups = const [];
  Map<String, Future<List<Map<String, dynamic>>> Function()> catalogByGroup =
      {};
  List<Map<String, String>> schools = const [];
  Object? schoolsError;
  Object? catalogError;
  Map<String, dynamic>? testJson;
  int fetchTestCalls = 0;
  bool online = true;
  int groupsCalls = 0;
  final List<String> events = [];

  @override
  Future<bool> ping() async => online;

  @override
  Future<List<Map<String, dynamic>>> fetchGroups(String schoolCode,
      {String? schoolId}) async {
    groupsCalls++;
    final e = groupsError;
    if (e != null) throw e;
    return groups;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId,
          {String? testKey}) async =>
      [
        {'id': 's1', 'student_code': 'S-1', 'name': 'Ali V'}
      ];

  @override
  Future<List<Map<String, String>>> fetchCatalogSchools(
      {bool strict = false}) async {
    final e = schoolsError;
    if (e != null) {
      if (strict) throw e;
      return [];
    }
    return schools;
  }

  @override
  Future<List<Map<String, dynamic>>> fetchTestCatalog(
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    final e = catalogError;
    if (e != null) throw e;
    final f = catalogByGroup[groupId ?? ''];
    if (f == null) return [];
    return f();
  }

  @override
  Future<Map<String, dynamic>?> fetchTest(String testKey,
      {String? groupId,
      String? schoolCode,
      String? schoolId,
      String? authToken}) async {
    fetchTestCalls++;
    events.add('fetchTest');
    return testJson;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MonitoringApi savedApi;
  late _Api fake;

  setUp(() {
    savedApi = api;
    fake = _Api();
    api = fake;
    SharedPreferences.setMockInitialValues({});
    TestCatalogService.resetKnownMissingForTest();
    TestCache.enterMemoryMode();
  });
  tearDown(() {
    api = savedApi;
    TestCache.exitMemoryMode();
  });

  Future<void> settle(WidgetTester tester, [int n = 6]) async {
    for (var i = 0; i < n; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  AppLocalizations l10n(WidgetTester tester) =>
      AppLocalizations.of(tester.element(find.byType(Scaffold).last))!;

  Future<(ProviderContainer, GoRouter)> boot(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: await appTestOverrides());
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const AlochiMonitoringApp(),
    ));
    await tester.pump();
    return (container, container.read(goRouterProvider));
  }

  int stackDepth(GoRouter r) =>
      r.routerDelegate.currentConfiguration.matches.length;

  Future<void> pumpGroupSelect(WidgetTester tester,
      {CatalogEntry? fallback}) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: GroupSelectScreen(
        schoolCode: '39',
        schoolLabel: '39-maktab',
        schoolId: 'uuid-39',
        fallbackEntry: fallback,
      ),
    ));
    await settle(tester, 3);
  }

  group('school picker', () {
    testWidgets('load failure -> localized retry banner, never raw text or '
        '"tests not found"', (tester) async {
      fake.catalogError = const ApiException(0, 'RAW DEBUG', code: kApiNetwork);
      fake.schoolsError = const ApiException(0, 'RAW DEBUG', code: kApiNetwork);
      final (_, router) = await boot(tester);
      router.push('/school_select');
      await settle(tester);

      final t = l10n(tester);
      expect(find.text(t.connectionError), findsOneWidget);
      expect(find.textContaining('RAW DEBUG'), findsNothing);
      expect(find.text(t.testsNotFound), findsNothing);

      fake.catalogError = null;
      fake.schoolsError = null;
      fake.schools = [
        {'school_code': '39', 'label': '39-maktab', 'school_id': 'u39'}
      ];
      await tester.tap(find.text(t.retry));
      await settle(tester);
      expect(find.text('39-maktab'), findsOneWidget);
      expect(find.text(t.connectionError), findsNothing);
    });

    testWidgets('a double tap on a school pushes the setup screen once',
        (tester) async {
      fake.schools = [
        {'school_code': '39', 'label': '39-maktab', 'school_id': 'u39'}
      ];
      final (_, router) = await boot(tester);
      router.push('/school_select');
      await settle(tester);
      final before = stackDepth(router);

      await tester.tap(find.text('39-maktab'));
      await tester.tap(find.text('39-maktab'), warnIfMissed: false);
      await settle(tester);

      expect(stackDepth(router), before + 1);
      expect(find.byType(SessionSetupScreen), findsOneWidget);
    });

    testWidgets('double Enter on the PIN moves to group select once',
        (tester) async {
      fake.schools = [
        {'school_code': '39', 'label': '39-maktab', 'school_id': 'u39'}
      ];
      fake.groups = [
        {'id': 'g1', 'name': '5-A'}
      ];
      final (_, router) = await boot(tester);
      router.push('/school_select');
      await settle(tester);
      await tester.tap(find.text('39-maktab'));
      await settle(tester);

      final field = find.byType(TextField);
      await tester.enterText(field, '3939');
      final before = stackDepth(router);
      final submit = tester.widget<TextField>(field).onSubmitted!;
      submit('3939');
      submit('3939');
      await settle(tester, 8);

      expect(find.byType(GroupSelectScreen), findsOneWidget);
      // pushReplacement of setup: depth unchanged, and only ONE group screen
      // was ever created (a second Enter used to replace it with another).
      expect(stackDepth(router), before);
      expect(fake.groupsCalls, 1);
    });
  });

  group('group select', () {
    testWidgets('groups load failure: retry banner (ARB text), Retry reloads',
        (tester) async {
      fake.groupsError = const ApiException(503, 'RAW DEBUG');
      await pumpGroupSelect(tester);
      final t = l10n(tester);
      expect(find.text(t.groupSelectGroupsLoadFailed), findsOneWidget);
      expect(find.text(t.retry), findsOneWidget);
      expect(find.textContaining('RAW DEBUG'), findsNothing);

      fake.groupsError = null;
      fake.groups = [
        {'id': 'g1', 'name': '5-A'}
      ];
      await tester.tap(find.text(t.retry));
      await settle(tester, 3);
      expect(find.text('5-A'), findsOneWidget);
      expect(find.text(t.groupSelectGroupsLoadFailed), findsNothing);
    });

    testWidgets('offline with a remembered group list: groups still shown',
        (tester) async {
      await tester.runAsync(() => GroupsCache.save('39', 'uuid-39', [
            {'id': 'g1', 'name': '5-A'}
          ]));
      fake.groupsError = const ApiException(0, 'x', code: kApiNetwork);
      await pumpGroupSelect(tester);
      expect(find.text('5-A'), findsOneWidget);
      expect(find.text(l10n(tester).groupSelectGroupsLoadFailed), findsNothing);
      // The stale list is labelled, with a retry that picks up the server.
      final t = l10n(tester);
      expect(find.text(t.offlineRosterBanner), findsOneWidget);
      fake.groupsError = null;
      fake.groups = [
        {'id': 'g1', 'name': '5-A'},
        {'id': 'g2', 'name': '6-B'},
      ];
      await tester.tap(find.text(t.retry));
      await settle(tester, 3);
      expect(find.text('6-B'), findsOneWidget);
      expect(find.text(t.offlineRosterBanner), findsNothing);
    });

    testWidgets('a real "no" from the server (404) is not answered with the '
        'remembered list', (tester) async {
      await tester.runAsync(() => GroupsCache.save('39', 'uuid-39', [
            {'id': 'g1', 'name': '5-A'}
          ]));
      fake.groupsError = const ApiException(404, 'gone');
      await pumpGroupSelect(tester);
      expect(find.text('5-A'), findsNothing);
      expect(find.text(l10n(tester).groupSelectGroupsLoadFailed),
          findsOneWidget);
    });

    testWidgets('a school without groups goes straight to the roster with the '
        'fallback test (router passes selectedCatalogEntryProvider)',
        (tester) async {
      fake.groups = const [];
      final (container, router) = await boot(tester);
      container.read(selectedCatalogEntryProvider.notifier).state =
          const CatalogEntry(
        testKey: 'general_1',
        title: 'General',
        grade: 5,
        version: 1,
        status: CatalogStatus.cachedOnly,
      );
      router.push('/group_select/39', extra: {'schoolLabel': '39'});
      await settle(tester, 8);
      expect(find.byType(StudentEntryScreen), findsOneWidget);
      expect(
          tester
              .widget<StudentEntryScreen>(find.byType(StudentEntryScreen))
              .session
              .testKey,
          'general_1');
    });

    testWidgets('a slow answer for a group already left is ignored',
        (tester) async {
      fake.groups = [
        {'id': 'a', 'name': 'Group-A'},
        {'id': 'b', 'name': 'Group-B'},
      ];
      final slowA = Completer<List<Map<String, dynamic>>>();
      fake.catalogByGroup = {
        'a': () => slowA.future,
        'b': () async => [_item('kb', 'Test-B')],
      };
      await pumpGroupSelect(tester);
      await tester.tap(find.text('Group-A'));
      await settle(tester, 2);
      await tester.tap(find.text('Group-B'));
      await settle(tester, 3);
      expect(find.text('Test-B'), findsOneWidget);

      slowA.complete([_item('ka', 'Test-A')]);
      await settle(tester, 3);
      expect(find.text('Test-A'), findsNothing);
      expect(find.text('Test-B'), findsOneWidget);
    });

    testWidgets('download failure shows the downloadError toast',
        (tester) async {
      fake.groups = [
        {'id': 'a', 'name': 'Group-A'}
      ];
      fake.catalogByGroup = {'a': () async => [_item('ka', 'Test-A')]};
      fake.testJson = null; // fetchTest -> null -> download() == false
      await pumpGroupSelect(tester);
      await tester.tap(find.text('Group-A'));
      await settle(tester, 3);
      final t = l10n(tester);
      await tester.tap(find.text(t.download));
      await settle(tester, 3);
      expect(find.text(t.downloadError), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    group('updatable test', () {
      Future<void> openGroup(WidgetTester tester) async {
        fake.groups = [
          {'id': 'a', 'name': 'Group-A'}
        ];
        fake.catalogByGroup = {
          'a': () async => [_item('ka', 'Test-A', version: 2)]
        };
        await tester.runAsync(() => TestCache.upsert(
            'ka', 'Test-A', 5, 1, '{"version":1}')); // older cached copy
        await pumpGroupSelect(tester);
        await tester.tap(find.text('Group-A'));
        await settle(tester, 3);
      }

      testWidgets('is re-downloaded BEFORE the roster opens', (tester) async {
        fake.testJson = _playable(2);
        await openGroup(tester);
        await tester.tap(find.text('Test-A'));
        await settle(tester, 6);
        expect(fake.fetchTestCalls, 1);
        expect(await TestCache.versionOf('ka'), 2);
        expect(find.byType(StudentEntryScreen), findsOneWidget);
      });

      testWidgets('online + failed download: toast, roster not opened',
          (tester) async {
        fake.testJson = null;
        fake.online = true;
        await openGroup(tester);
        await tester.tap(find.text('Test-A'));
        await settle(tester, 4);
        expect(find.text(l10n(tester).downloadError), findsOneWidget);
        expect(find.byType(StudentEntryScreen), findsNothing);
        expect(await TestCache.versionOf('ka'), 1);
        await tester.pump(const Duration(seconds: 5));
      });

      testWidgets('offline: the cached copy is used', (tester) async {
        fake.testJson = null;
        fake.online = false;
        await openGroup(tester);
        await tester.tap(find.text('Test-A'));
        await settle(tester, 6);
        expect(find.byType(StudentEntryScreen), findsOneWidget);
        expect(await TestCache.versionOf('ka'), 1);
      });
    });

    testWidgets('a double tap on a test card opens the roster once',
        (tester) async {
      fake.groups = [
        {'id': 'a', 'name': 'Group-A'}
      ];
      fake.catalogByGroup = {'a': () async => [_item('ka', 'Test-A')]};
      await tester.runAsync(
          () => TestCache.upsert('ka', 'Test-A', 5, 1, '{"version":1}'));
      await pumpGroupSelect(tester);
      await tester.tap(find.text('Group-A'));
      await settle(tester, 3);

      await tester.tap(find.text('Test-A'));
      await tester.tap(find.text('Test-A'), warnIfMissed: false);
      await settle(tester, 6);
      expect(find.byType(StudentEntryScreen), findsOneWidget);
      // popping once must reveal group select, not a second roster
      Navigator.of(tester.element(find.byType(StudentEntryScreen))).pop();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(StudentEntryScreen), findsNothing);
      expect(find.byType(GroupSelectScreen), findsOneWidget);
    });
  });
}
