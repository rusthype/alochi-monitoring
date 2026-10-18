// Offline diagnostic roster "done" signal (derived from the pack chain), the
// retake confirm / selection reset on the roster screen, and the pack-open
// race fixes (concurrent opens, failed second open keeps the first session).
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/offline/offline_diagnostic_api.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_student_select_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _school = '00000000-0000-4000-8000-0000000000b2';
const _g1 = '00000000-0000-4000-8000-0000000000c1';
const _s1 = '00000000-0000-4000-8000-0000000000d1';
const _s2 = '00000000-0000-4000-8000-0000000000d2';
const _packUuid = '00000000-0000-4000-8000-0000000000a1';

Map<String, dynamic> _diag(String subject) => {
      'type': 'diagnostic',
      'key': 'diag:$subject:g5:uz:v1',
      'catalog': {},
      'data': {
        'questions': [
          {
            'id': '$subject-q1',
            'question_text': 'Q1',
            'options': ['a', 'b', 'c', 'd'],
          },
        ]
      },
    };

LoadedPack _pack() => LoadedPack(
      manifest: PackManifest(
        formatVersion: 1,
        packUuid: _packUuid,
        schoolId: _school,
        schoolCode: '999',
        createdAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2099, 1, 1),
        kdfIter: 1,
        kdfSalt: Uint8List(16),
        files: const {},
      ),
      tests: [_diag('math'), _diag('english')],
      groups: [
        {'id': _g1, 'name': '5-A', 'grade': 5},
      ],
      students: [
        {'id': _s1, 'code': 'A-0001', 'name': 'Valiyev Ali', 'group_id': _g1},
        {'id': _s2, 'code': 'A-0002', 'name': 'Karimov Bobur', 'group_id': _g1},
      ],
      chainKey: Uint8List.fromList(List.generate(32, (i) => 100 + i)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late DiagnosticKioskApi savedDiag;
  late MonitoringApi savedApi;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('offline_roster_done_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    await DiagnosticAnswerStore.openInMemory();
    savedDiag = diagnosticKioskApi;
    savedApi = api;
  });

  tearDown(() async {
    OfflinePackSession.close();
    diagnosticKioskApi = savedDiag;
    api = savedApi;
    parkedOnlineApi = null;
    await DiagnosticAnswerStore.reset();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Directory media() => Directory(p.join(tmp.path, 'media'));

  group('roster status from the chain', () {
    test('not_started -> partial(next) -> completed, per student', () async {
      await OfflinePackSession.open(_pack(), media());
      final k = diagnosticKioskApi;
      Future<Map<String, dynamic>> row(String name) async {
        final (rows, _) = await k.listStudents(_school, '5-A');
        return rows.firstWhere((r) => r['student_name'] == name);
      }

      var ali = await row('Valiyev Ali');
      expect(ali['status'], 'not_started');
      final attemptId = ali['attempt_id'] as String;

      Future<void> finish(String subject) =>
          k.finishAttempt(attemptId: attemptId, answers: [
            {'question_id': '$subject-q1', 'selected': 'A'}
          ]);

      await finish('math');
      ali = await row('Valiyev Ali');
      expect(ali['status'], 'partial');
      expect(ali['next_subject'], 'english');

      await finish('english');
      ali = await row('Valiyev Ali');
      expect(ali['status'], 'completed');
      expect(ali['next_subject'], '');
      expect((await row('Karimov Bobur'))['status'], 'not_started');
    });
  });

  group('open() races', () {
    test('concurrent opens leave one coherent session; close restores online',
        () async {
      final online = MonitoringApi();
      api = online;
      await Future.wait([
        OfflinePackSession.open(_pack(), media()),
        OfflinePackSession.open(_pack(), media()),
      ]);
      expect(OfflinePackSession.isActive, isTrue);
      // The second open must have parked the REAL client, not the first
      // session's offline api.
      expect(parkedOnlineApi, same(online));
      OfflinePackSession.close();
      expect(api, same(online));
      expect(OfflinePackSession.isActive, isFalse);
    });

    test('a failed second open never closes the active session', () async {
      final online = MonitoringApi();
      api = online;
      final first = await OfflinePackSession.open(_pack(), media());
      await OfflineQueue.resetForTest(); // registerPack of the next open throws
      await expectLater(
          OfflinePackSession.open(_pack(), media()), throwsA(anything));
      expect(OfflinePackSession.current, same(first));
      expect(diagnosticKioskApi, isA<OfflineDiagnosticKioskApi>());
      expect(parkedOnlineApi, same(online));
    });
  });

  group('roster screen', () {
    Future<void> pump(WidgetTester tester, List<Map<String, dynamic>> students,
        {required GoRouter router}) async {
      await tester.pumpWidget(MaterialApp.router(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    GoRouter routerFor(
        List<Map<String, dynamic>> Function() students, List<String> pushed) {
      Widget roster(Map<String, dynamic> extra) =>
          DiagnosticStudentSelectScreen(
            schoolId: _school,
            schoolName: '999',
            classLabel: '5-A',
            language: 'uz',
            listStudentsOverride: (_, __) async => (students(), false),
            availableSubjectsOverride: (g, {String language = 'uz'}) async =>
                {'subjects': <String>[]},
            peekSubjectOverride: (
                    {required attemptId, required subject}) async =>
                {'fixed_variant': true, 'questions': []},
            connectivityStreamOverride: const Stream.empty(),
          );
      return GoRouter(initialLocation: '/roster', routes: [
        GoRoute(
            path: '/roster',
            builder: (c, s) => roster(s.extra as Map<String, dynamic>? ?? {})),
        GoRoute(
            path: '/diagnostic_test_runner',
            builder: (c, s) {
              pushed.add((s.extra as Map)['attemptId'] as String);
              return const Scaffold(body: Text('RUNNER'));
            }),
      ]);
    }

    testWidgets(
        'completed student: confirm before a new attempt; selection '
        'cleared and roster reloaded after the finished screen returns',
        (tester) async {
      await tester.runAsync(() => OfflinePackSession.open(_pack(), media()));
      var students = [
        {
          'attempt_id': 'a1',
          'student_name': 'Valiyev Ali',
          'status': 'completed',
          'next_subject': '',
        },
      ];
      final pushed = <String>[];
      final router = routerFor(() => students, pushed);
      await pump(tester, students, router: router);
      final l10n =
          AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

      await tester.tap(find.textContaining('Ali'));
      await tester.pump();
      await tester.tap(find.text(l10n.diagnosticStartTest));
      await tester.pumpAndSettle();
      // dialog asks first; cancel -> no attempt
      expect(find.text(l10n.diagnosticRetakeTitle), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(pushed, isEmpty);

      // confirm -> runner pushed
      await tester.tap(find.text(l10n.diagnosticStartTest));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.diagnosticRetakeConfirm));
      await tester.pumpAndSettle();
      expect(pushed, ['a1']);

      // "finished screen" returns with go() to the same route
      students = [
        {
          'attempt_id': 'a1',
          'student_name': 'Valiyev Ali',
          'status': 'completed',
          'next_subject': '',
        },
        {
          'attempt_id': 'a2',
          'student_name': 'Karimov Bobur',
          'status': 'not_started',
          'next_subject': '',
        },
      ];
      router.go('/roster', extra: {'again': true});
      await tester.pumpAndSettle();
      expect(find.textContaining('Bobur'), findsOneWidget);
      // nothing selected any more: Start is disabled
      await tester.tap(find.text(l10n.diagnosticStartTest));
      await tester.pumpAndSettle();
      expect(pushed, ['a1']);
      expect(find.text(l10n.diagnosticRetakeTitle), findsNothing);
    });
  });
}
