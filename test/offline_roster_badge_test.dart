// Normal monitoring-test roster in pack mode: "done" marker from the chain,
// retake confirm, and the diagnostic "download all" button hidden offline.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_student_select_screen.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/features/session/test_session.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _school = '00000000-0000-4000-8000-0000000000b2';
const _g1 = '00000000-0000-4000-8000-0000000000c1';
const _s1 = '00000000-0000-4000-8000-0000000000d1';
const _s2 = '00000000-0000-4000-8000-0000000000d2';
const _packUuid = '00000000-0000-4000-8000-0000000000a1';
const _testKey = 'mon:t1';

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
      tests: const [],
      groups: [
        {'id': _g1, 'name': '5-A', 'grade': 5},
      ],
      students: [
        {'id': _s1, 'code': 'A-0001', 'name': 'Valiyev Ali', 'group_id': _g1},
        {'id': _s2, 'code': 'A-0002', 'name': 'Karimov Bobur', 'group_id': _g1},
      ],
      chainKey: Uint8List.fromList(List.generate(32, (i) => 100 + i)),
    );

Map<String, dynamic> _payload(String studentId, String testKey) => {
      'student_id': studentId,
      'detail': {'test_key': testKey},
    };

const _session = TestSession(
  testKey: _testKey,
  title: 'T',
  runnerType: 'engine',
  schoolCode: '999',
  schoolLabel: '999',
  testGrade: 5,
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
    tmp = Directory.systemTemp.createTempSync('offline_roster_badge_');
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

  test('finishedStudentIds: true after a stored attempt, false otherwise',
      () async {
    final s = await OfflinePackSession.open(_pack(), media());
    expect(await s.finishedStudentIds(_testKey), isEmpty);

    await s.recordResult(_payload(_s1, _testKey), token: 'tok-1');
    await s.recordResult(_payload(_s2, 'other:test'), token: 'tok-2');
    expect(await s.finishedStudentIds(_testKey), {_s1});

    // A retake is a second row with a fresh random key, not a dedup hit.
    await s.recordResult(_payload(_s1, _testKey), token: 'tok-3');
    expect(await s.finishedStudentIds(_testKey), {_s1});
    expect((await s.finishedStudentIds('other:test')), {_s2});
  });

  group('student_entry_screen', () {
    // Host: a button that pushes the roster; it stays on screen after a
    // launch returns or a retake is cancelled.
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                builder: (_) => const StudentEntryScreen(
                  session: _session,
                  preselectedGroup: {'id': _g1, 'name': '5-A'},
                ),
              )),
              child: const Text('OPEN'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('OPEN'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    Future<AppLocalizations> openRoster(WidgetTester tester) async {
      final s = await tester
          .runAsync(() => OfflinePackSession.open(_pack(), media()));
      await tester.runAsync(
          () => s!.recordResult(_payload(_s1, _testKey), token: 'tok-1'));
      await pump(tester);
      await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 200))); // let the roster load
      await tester.pump(const Duration(milliseconds: 400));
      return AppLocalizations.of(tester.element(find.byType(Scaffold).last))!;
    }

    testWidgets('badge on the finished student only; unfinished: no dialog',
        (tester) async {
      final l10n = await openRoster(tester);
      expect(find.text(l10n.rosterDoneBadge), findsOneWidget);

      await tester.tap(find.textContaining('Bobur'));
      await tester.pump();
      await tester.tap(find.text(l10n.startTest));
      await tester.pump();
      expect(find.text(l10n.diagnosticRetakeTitle), findsNothing);
      // let the (bailing) launcher finish so no async work outlives the test
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle(const Duration(seconds: 5));
    });

    testWidgets('finished student: retake dialog, cancel then confirm',
        (tester) async {
      final l10n = await openRoster(tester);
      await tester.tap(find.textContaining('Ali'));
      await tester.pump();
      await tester.tap(find.text(l10n.startTest));
      await tester.pumpAndSettle();
      expect(find.text(l10n.diagnosticRetakeTitle), findsOneWidget);
      expect(find.text(l10n.testRetakeBody), findsOneWidget);
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(find.text(l10n.diagnosticRetakeTitle), findsNothing);
      expect(find.byType(StudentEntryScreen), findsOneWidget);

      // confirm proceeds to launch (nothing cached in this harness -> the
      // launcher bails and the roster STAYS on the same group/test).
      await tester.tap(find.text(l10n.startTest));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.diagnosticRetakeConfirm));
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 300)));
      await tester.pumpAndSettle(const Duration(seconds: 5));
      expect(find.byType(StudentEntryScreen), findsOneWidget);
      expect(find.text(l10n.rosterDoneBadge), findsOneWidget);
    });
  });

  group('diagnostic roster: download-all button', () {
    Future<void> pump(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: DiagnosticStudentSelectScreen(
          schoolId: _school,
          schoolName: '999',
          classLabel: '5-A',
          language: 'uz',
          listStudentsOverride: (_, __) async => (
            [
              {
                'attempt_id': 'a1',
                'student_name': 'Valiyev Ali',
                'status': 'not_started',
                'next_subject': '',
              },
            ],
            false
          ),
          availableSubjectsOverride: (g, {String language = 'uz'}) async =>
              {'subjects': <String>[]},
          peekSubjectOverride: ({required attemptId, required subject}) async =>
              {'fixed_variant': true, 'questions': []},
          connectivityStreamOverride: const Stream.empty(),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('shown online, hidden in pack mode', (tester) async {
      await pump(tester);
      final l10n =
          AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;
      expect(find.text(l10n.diagnosticDownloadAllOffline), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => OfflinePackSession.open(_pack(), media()));
      await pump(tester);
      expect(find.text(l10n.diagnosticDownloadAllOffline), findsNothing);
    });
  });
}
