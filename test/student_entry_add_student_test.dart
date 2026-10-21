// StudentEntryScreen "Bola qo'shish": the new add flow replaces the anonymous
// manual-name path. Fake api + addStudentOverride, no network, no real DB.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/local_students_db.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/models/add_student.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/features/session/test_session.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _session = TestSession(
  testKey: 't',
  title: 'T',
  runnerType: 'engine',
  schoolCode: '999',
  schoolLabel: '999',
  testGrade: 4,
);

class _RosterApi extends MonitoringApi {
  @override
  Future<List<Map<String, dynamic>>> fetchStudents(String groupId) async => [
        {
          'id': 's1',
          'name': 'Aliyev Ali',
          'first_name': 'Ali',
          'last_name': 'Aliyev'
        },
        {'id': 's2', 'name': 'Pending Kid', 'pending': true},
      ];
}

void main() {
  late MonitoringApi saved;
  setUp(() {
    saved = api;
    api = _RosterApi();
  });
  tearDown(() => api = saved);

  Future<AppLocalizations> pump(
    WidgetTester tester,
    Future<AddStudentResult> Function({
      required String groupId,
      required AddStudentDraft draft,
      required bool confirmNew,
    }) add,
  ) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StudentEntryScreen(
        session: _session,
        preselectedGroup: const {'id': 'g1', 'name': '4-A'},
        addStudentOverride: add,
      ),
    ));
    // Let the roster load (fetchStudents + the local-students lookup, which
    // fails soft without a DB in this harness).
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 400));
    return AppLocalizations.of(
        tester.element(find.byType(StudentEntryScreen)))!;
  }

  Future<void> addViaDialog(WidgetTester tester,
      {String last = 'Karimov', String first = 'Vali'}) async {
    await tester.ensureVisible(find.byKey(const Key('addStudentButton')));
    await tester.tap(find.byKey(const Key('addStudentButton')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('addStudentLastName')), last);
    await tester.enterText(find.byKey(const Key('addStudentFirstName')), first);
    await tester.ensureVisible(find.byKey(const Key('addStudentSubmit')));
    await tester.tap(find.byKey(const Key('addStudentSubmit')));
    await tester.pumpAndSettle();
  }

  testWidgets('server pending rows show the badge; plain rows do not',
      (tester) async {
    await pump(
        tester,
        ({required groupId, required draft, required confirmNew}) async =>
            throw StateError('unused'));
    expect(find.text('Pending Kid'), findsOneWidget);
    expect(find.byKey(const Key('pendingBadge')), findsOneWidget);
  });

  testWidgets('add: group id + draft reach the api, child appears pending',
      (tester) async {
    String? gotGroup;
    AddStudentDraft? gotDraft;
    final l10n = await pump(tester, (
        {required groupId, required draft, required confirmNew}) async {
      gotGroup = groupId;
      gotDraft = draft;
      return const AddStudentResult(
        id: 'srv-9',
        name: 'Karimov Vali',
        firstName: 'Vali',
        lastName: 'Karimov',
        pending: true,
      );
    });
    await addViaDialog(tester);

    expect(gotGroup, 'g1');
    expect(gotDraft!.lastName, 'Karimov');
    expect(gotDraft!.clientTempId, startsWith('new:'));
    expect(find.text('Karimov Vali'), findsOneWidget);
    // two pending rows now: the server one and the new one.
    expect(find.byKey(const Key('pendingBadge')), findsNWidgets(2));
    expect(find.text(l10n.addStudentQueuedNotice), findsNothing);
  });

  testWidgets('added while offline: queued notice is shown', (tester) async {
    final l10n = await pump(tester, (
        {required groupId, required draft, required confirmNew}) async {
      return AddStudentResult(
        id: draft.clientTempId,
        name: 'Karimov Vali',
        firstName: 'Vali',
        lastName: 'Karimov',
        queuedLocally: true,
      );
    });
    await addViaDialog(tester);
    expect(find.text(l10n.addStudentQueuedNotice), findsOneWidget);
    expect(find.text('Karimov Vali'), findsOneWidget);
  });

  testWidgets('"Bu shumi?" -> existing student: no new row, nothing resent',
      (tester) async {
    var calls = 0;
    await pump(tester, (
        {required groupId, required draft, required confirmNew}) async {
      calls++;
      throw const SimilarStudentsException([
        SimilarStudent(
            id: 's1', name: 'Aliyev Ali', grade: 4, groupName: '4-A'),
      ]);
    });
    await tester.ensureVisible(find.byKey(const Key('addStudentButton')));
    await tester.tap(find.byKey(const Key('addStudentButton')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const Key('addStudentLastName')), 'Aliyev');
    await tester.enterText(find.byKey(const Key('addStudentFirstName')), 'Ali');
    await tester.ensureVisible(find.byKey(const Key('addStudentSubmit')));
    await tester.tap(find.byKey(const Key('addStudentSubmit')));
    await tester.pumpAndSettle();

    // candidate tile (inside the dialog)
    await tester.tap(find.descendant(
        of: find.byType(Dialog), matching: find.text('Aliyev Ali')));
    await tester.pumpAndSettle();

    expect(calls, 1);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('Aliyev Ali'), findsOneWidget); // still one roster row
    expect(find.byKey(const Key('pendingBadge')), findsOneWidget);
  });

  testWidgets('no anonymous start: Boshlash stays disabled without a student',
      (tester) async {
    final l10n = await pump(
        tester,
        ({required groupId, required draft, required confirmNew}) async =>
            throw StateError('unused'));
    final inkWell = tester.widget<InkWell>(find.ancestor(
        of: find.text(l10n.startTest), matching: find.byType(InkWell)));
    expect(inkWell.onTap, isNull);
  });

  testWidgets('roster merges children added offline (not yet synced)',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = Directory.systemTemp.createTempSync('entry_local_');
    addTearDown(() async {
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });
    await tester.runAsync(() async {
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      await LocalStudentsDb.add(const LocalStudent(
          tempId: 'new:L1',
          groupId: 'g1',
          firstName: 'Vali',
          lastName: 'Local'));
      // synced one and another group's one must not show
      await LocalStudentsDb.add(const LocalStudent(
          tempId: 'new:L2',
          groupId: 'g1',
          firstName: 'Done',
          lastName: 'Synced',
          serverId: 'srv'));
      await LocalStudentsDb.add(const LocalStudent(
          tempId: 'new:L3',
          groupId: 'g2',
          firstName: 'Other',
          lastName: 'Group'));
    });
    await pump(
        tester,
        ({required groupId, required draft, required confirmNew}) async =>
            throw StateError('unused'));
    expect(find.text('Local Vali'), findsOneWidget);
    expect(find.text('Synced Done'), findsNothing);
    expect(find.text('Group Other'), findsNothing);
    expect(find.byKey(const Key('pendingBadge')), findsNWidgets(2));
  });
}
