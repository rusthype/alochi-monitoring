// A class whose (known) grade has no diagnostics in the offline pack is "no
// tests": it never borrows another grade's diagnostic (the server rejects that
// result at import as group_invalid). Unknown grade keeps the legacy fallback.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/api/api_client.dart' show ApiException;
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/models/add_student.dart';
import 'package:alochi_monitoring/core/offline/offline_errors.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_class_select_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _packUuid = '00000000-0000-4000-8000-0000000000a1';
const _school = '00000000-0000-4000-8000-0000000000b2';
const _g3 = '00000000-0000-4000-8000-0000000000c3';
const _g4 = '00000000-0000-4000-8000-0000000000c4';
const _gx = '00000000-0000-4000-8000-0000000000c5';

Map<String, dynamic> _diag(String subject, int grade) => {
      'type': 'diagnostic',
      'key': 'diag:$subject:g$grade:uz:v1',
      'catalog': {},
      'data': {
        'questions': [
          {
            'id': '$subject-g$grade-q1',
            'topic': 't',
            'level': 1,
            'question_text': 'Q1',
            'options': ['a', 'b', 'c', 'd'],
            'image': '',
            'svg_visual': '',
          },
        ],
      },
    };

LoadedPack _pack(List<Map<String, dynamic>> groups) => LoadedPack(
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
      // Grade-4 tests only.
      tests: [_diag('math', 4), _diag('english', 4)],
      groups: groups,
      students: [
        for (final g in groups)
          {
            'id': 's-${g['id']}',
            'code': 'C',
            'name': 'Student ${g['name']}',
            'group_id': g['id'],
          },
      ],
      chainKey: Uint8List.fromList(List.generate(32, (i) => 100 + i)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late DiagnosticKioskApi saved;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('offline_class_no_tests_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    await DiagnosticAnswerStore.openInMemory();
    saved = diagnosticKioskApi;
  });

  tearDown(() async {
    OfflinePackSession.close();
    diagnosticKioskApi = saved;
    await DiagnosticAnswerStore.reset();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<DiagnosticKioskApi> open(LoadedPack pack) async {
    await OfflinePackSession.open(pack, Directory(p.join(tmp.path, 'media')));
    return diagnosticKioskApi;
  }

  final groups = [
    {'id': _g3, 'name': '3-B', 'grade': 3},
    {'id': _g4, 'name': '4-A', 'grade': 4},
  ];

  test('grade-3 class in a grade-4-only pack has no tests', () async {
    final k = await open(_pack(groups));

    expect((await k.availableSubjects(3))['subjects'], isEmpty);
    expect((await k.availableSubjects(4))['subjects'], ['math', 'english']);

    final (classes, _) = await k.listClasses(_school);
    final byLabel = {for (final c in classes) c['class_label']: c};
    expect(byLabel['3-B']!['no_tests'], true);
    expect(byLabel['4-A']!.containsKey('no_tests'), false);

    // The 3-B child is not given the grade-4 test.
    final (rows3, _) = await k.listStudents(_school, '3-B');
    expect(rows3.single['next_subject'], '');
    await expectLater(
      k.startAttempt(attemptId: rows3.single['attempt_id'], subject: 'math'),
      throwsA(
          isA<ApiException>().having((e) => e.code, 'code', kOfflineNotFound)),
    );
  });

  test('addStudent into a class without tests throws class_without_tests',
      () async {
    final k = await open(_pack(groups));
    const draft = AddStudentDraft(
        firstName: 'Ali', lastName: 'Valiyev', clientTempId: 'new:1');
    await expectLater(
      k.addStudent(
          schoolId: _school,
          classLabel: '3-B',
          language: 'uz',
          draft: draft,
          confirmNew: true),
      throwsA(isA<ApiException>()
          .having((e) => e.code, 'code', kClassWithoutTests)),
    );
    // Nothing was created locally.
    final (rows, _) = await k.listStudents(_school, '3-B');
    expect(rows, hasLength(1));
  });

  test('class with tests is unchanged: 4-A serves its grade-4 diagnostics',
      () async {
    final k = await open(_pack(groups));
    final (rows, _) = await k.listStudents(_school, '4-A');
    expect(rows.single['next_subject'], 'math');
    final att = await k.startAttempt(
        attemptId: rows.single['attempt_id'], subject: 'math');
    expect(att['test_key'], 'diag:math:g4:uz:v1');

    final added = await k.addStudent(
      schoolId: _school,
      classLabel: '4-A',
      language: 'uz',
      draft: const AddStudentDraft(
          firstName: 'Vali', lastName: 'Aliyev', clientTempId: 'new:2'),
      confirmNew: true,
    );
    expect(added.classLabel, '4-A');
  });

  test('group with unknown grade keeps the all-grades fallback', () async {
    final k = await open(_pack([
      {'id': _gx, 'name': 'Boshlang\'ich'},
    ]));
    final (classes, _) = await k.listClasses(_school);
    expect(classes.single.containsKey('no_tests'), false);
    final (rows, _) = await k.listStudents(_school, 'Boshlang\'ich');
    expect(rows.single['next_subject'], 'math');
    final att = await k.startAttempt(
        attemptId: rows.single['attempt_id'], subject: 'math');
    expect(att['test_key'], 'diag:math:g4:uz:v1');
  });

  testWidgets('class select shows a no-tests class disabled with the message',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    diagnosticKioskApi = _FakeClassesApi();
    var pushed = false;
    final router = GoRouter(
      initialLocation: '/c',
      routes: [
        GoRoute(
          path: '/c',
          builder: (_, __) => const DiagnosticClassSelectScreen(
              schoolId: 's1', schoolName: 'Maktab 1'),
        ),
        GoRoute(
          path: '/diagnostic_student_select',
          builder: (_, __) {
            pushed = true;
            return const Scaffold(body: Text('STUDENTS'));
          },
        ),
      ],
    );
    await tester.pumpWidget(ProviderScope(
      overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      child: MaterialApp.router(
        routerConfig: router,
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('3-B'));
    await tester.pumpAndSettle();
    expect(
      find.text(
          "Bu sinf uchun paketda test yo'q. Panelda shu sinf darajasi uchun yangi paket yarating."),
      findsOneWidget,
    );
    expect(pushed, false);

    await tester.tap(find.text('4-A'));
    await tester.pumpAndSettle();
    expect(pushed, true);
  });
}

class _FakeClassesApi extends DiagnosticKioskApi {
  @override
  Future<(List<Map<String, dynamic>>, bool)> listClasses(
          String schoolId) async =>
      (
        <Map<String, dynamic>>[
          {'class_label': '3-B', 'language': 'uz', 'no_tests': true},
          {'class_label': '4-A', 'language': 'uz'},
        ],
        false
      );
}
