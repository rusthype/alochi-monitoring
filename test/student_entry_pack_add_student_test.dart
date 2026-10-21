// StudentEntryScreen inside an open USB pack: "Bola qo'shish" is available
// (it used to be hidden in offline mode) and adds a LOCAL pending child to the
// pack session - no HTTP, no local_queue row.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/features/session/student_entry_screen.dart';
import 'package:alochi_monitoring/features/session/test_session.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _gA = '00000000-0000-4000-8000-0000000000c1';
const _gB = '00000000-0000-4000-8000-0000000000c2';

const _session = TestSession(
  testKey: 't',
  title: 'T',
  runnerType: 'engine',
  schoolCode: '999',
  schoolLabel: '999',
  testGrade: 5,
);

LoadedPack _pack() => LoadedPack(
      manifest: PackManifest(
        formatVersion: 1,
        packUuid: '00000000-0000-4000-8000-0000000000a1',
        schoolId: '00000000-0000-4000-8000-0000000000b2',
        schoolCode: '999',
        createdAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2099, 1, 1),
        kdfIter: 1,
        kdfSalt: Uint8List(16),
        files: const {},
      ),
      tests: const [],
      groups: [
        {'id': _gA, 'name': '5-A', 'grade': 5},
        {'id': _gB, 'name': '5-B', 'grade': 5},
      ],
      students: [
        {'id': 's1', 'code': 'C1', 'name': 'Valiyev Ali', 'group_id': _gA},
        {'id': 's3', 'code': 'C3', 'name': 'Rahimov Sardor', 'group_id': _gB},
      ],
      chainKey: Uint8List.fromList(List.generate(32, (i) => 100 + i)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('entry_pack_add_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
  });

  tearDown(() async {
    OfflinePackSession.close();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<void> real(WidgetTester t, [int ms = 250]) async {
    await t.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await t.pump(const Duration(milliseconds: 300));
  }

  Future<void> pumpScreen(WidgetTester t) async {
    await t.runAsync(() =>
        OfflinePackSession.open(_pack(), Directory(p.join(tmp.path, 'm'))));
    await t.pumpWidget(const MaterialApp(
      locale: Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StudentEntryScreen(
        session: _session,
        preselectedGroup: {'id': _gA, 'name': '5-A'},
      ),
    ));
    await real(t);
  }

  Future<void> fillAndSubmit(WidgetTester t, String last, String first) async {
    await t.ensureVisible(find.byKey(const Key('addStudentButton')));
    await t.tap(find.byKey(const Key('addStudentButton')));
    await t.pumpAndSettle();
    await t.enterText(find.byKey(const Key('addStudentLastName')), last);
    await t.enterText(find.byKey(const Key('addStudentFirstName')), first);
    await t.ensureVisible(find.byKey(const Key('addStudentSubmit')));
    await t.tap(find.byKey(const Key('addStudentSubmit')));
    for (var i = 0; i < 4; i++) {
      await real(t, 300);
    }
  }

  testWidgets('pack mode shows the button; a new child is local + pending',
      (t) async {
    await pumpScreen(t);
    expect(find.text('Valiyev Ali'), findsOneWidget);
    expect(find.byKey(const Key('addStudentButton')), findsOneWidget);

    await fillAndSubmit(t, 'Yusupova', 'Nodira');

    expect(find.text('Yusupova Nodira'), findsOneWidget);
    expect(find.byKey(const Key('pendingBadge')), findsOneWidget);
    final local = OfflinePackSession.current!.localStudents;
    expect(local, hasLength(1));
    expect(local.single['group_id'], _gA);
    // nothing went to the online queue
    expect((await t.runAsync(OfflineQueue.pendingLocalCount)), 0);
  });

  testWidgets('a name matching the PARALLEL class asks "Bu shumi?"', (t) async {
    await pumpScreen(t);
    await fillAndSubmit(t, 'Rahimov', 'Sardor');
    // the candidate step is on screen, nothing was created
    expect(find.text('Rahimov Sardor'), findsWidgets);
    expect(OfflinePackSession.current!.localStudents, isEmpty);
  });
}
