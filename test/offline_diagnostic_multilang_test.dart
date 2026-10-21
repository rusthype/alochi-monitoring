// One pack, two languages: each roster student is served the diagnostics of
// their own `language` ('uz'/'ru'); packs without the field keep the old
// pack-wide default.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/offline/offline_diagnostic_api.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _packUuid = '00000000-0000-4000-8000-0000000000a1';
const _school = '00000000-0000-4000-8000-0000000000b2';
const _gA = '00000000-0000-4000-8000-0000000000c1';
const _gB = '00000000-0000-4000-8000-0000000000c2';

Map<String, dynamic> _diag(String subject, String lang) => {
      'type': 'diagnostic',
      'key': 'diag:$subject:g5:$lang:v1',
      'catalog': {},
      'data': {
        'questions': [
          {
            'id': '$subject-$lang-q1',
            'topic': 't',
            'level': 1,
            'question_text': 'Q1 $lang',
            'options': ['a', 'b', 'c', 'd'],
            'image': '',
            'svg_visual': '',
          },
        ],
      },
    };

Map<String, dynamic> _student(String id, String group, {String? language}) => {
      'id': id,
      'code': 'C-$id',
      'name': 'Student $id',
      'group_id': group,
      if (language != null) 'language': language,
    };

LoadedPack _pack({
  required List<Map<String, dynamic>> tests,
  required List<Map<String, dynamic>> groups,
  required List<Map<String, dynamic>> students,
}) =>
    LoadedPack(
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
      tests: tests,
      groups: groups,
      students: students,
      chainKey: Uint8List.fromList(List.generate(32, (i) => 100 + i)),
    );

final _bothLangs = [
  for (final l in ['uz', 'ru'])
    for (final s in ['math', 'english']) _diag(s, l),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late DiagnosticKioskApi saved;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('offline_diag_multilang_');
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
    expect(diagnosticKioskApi, isA<OfflineDiagnosticKioskApi>());
    return diagnosticKioskApi;
  }

  test('uz and ru students of ONE class each get their own language', () async {
    final k = await open(
      _pack(
        tests: _bothLangs,
        groups: [
          {'id': _gA, 'name': '5-A', 'grade': 5},
        ],
        students: [
          _student('s1', _gA, language: 'uz'),
          _student('s2', _gA, language: 'ru'),
          _student('s3', _gA, language: 'uz'),
        ],
      ),
    );

    // class language = majority (uz); one row for the label.
    final (classes, _) = await k.listClasses(_school);
    expect(classes, [
      {'class_label': '5-A', 'language': 'uz'},
    ]);

    final (rows, _) = await k.listStudents(_school, '5-A');
    final byName = {for (final r in rows) r['student_name']: r};
    expect(byName['Student s1']!['language'], 'uz');
    expect(byName['Student s1']!['attempt_id'], 'offline|s1|$_gA|uz');
    expect(byName['Student s2']!['language'], 'ru');
    expect(byName['Student s2']!['attempt_id'], 'offline|s2|$_gA|ru');
    expect(byName['Student s2']!['next_subject'], 'math');

    final uz = await k.startAttempt(
      attemptId: byName['Student s1']!['attempt_id'],
      subject: 'math',
    );
    final ru = await k.startAttempt(
      attemptId: byName['Student s2']!['attempt_id'],
      subject: 'math',
    );
    expect(uz['test_key'], 'diag:math:g5:uz:v1');
    expect(ru['test_key'], 'diag:math:g5:ru:v1');
    expect(((ru['questions'] as List).single as Map)['text'], 'Q1 ru');

    // peek (roster tap) follows the same language
    final peek = await k.peekSubject(
      attemptId: byName['Student s2']!['attempt_id'],
      subject: 'english',
    );
    expect(peek['test_key'], 'diag:english:g5:ru:v1');

    // the chain entry records the ru test for the ru student
    await k.finishAttempt(
      attemptId: byName['Student s2']!['attempt_id'],
      answers: [
        {'question_id': 'math-ru-q1', 'selected': 'B'},
      ],
    );
    final rowsDb = await PackResultsDb.rowsForPack(_packUuid);
    final payload = jsonDecode(rowsDb.single.payloadJson) as Map;
    expect(payload['test_key'], 'diag:math:g5:ru:v1');
    expect(payload['student_id'], 's2');

    // availableSubjects stays per-language
    expect((await k.availableSubjects(5, language: 'ru'))['subjects'], [
      'math',
      'english',
    ]);
  });

  test('class language follows the majority; ru-only class is ru', () async {
    final k = await open(
      _pack(
        tests: _bothLangs,
        groups: [
          {'id': _gA, 'name': '5-A', 'grade': 5},
          {'id': _gB, 'name': '5-B', 'grade': 5},
        ],
        students: [
          _student('s1', _gA, language: 'uz'),
          _student('s2', _gA, language: 'ru'),
          _student('s3', _gA, language: 'ru'),
          _student('s4', _gB, language: 'ru'),
        ],
      ),
    );
    final (classes, _) = await k.listClasses(_school);
    expect(
      {for (final c in classes) c['class_label']: c['language']},
      {'5-A': 'ru', '5-B': 'ru'},
    );
  });

  test(
    'old pack (no student.language): pack-wide default, as before',
    () async {
      final k = await open(
        _pack(
          tests: [_diag('math', 'ru'), _diag('english', 'ru')],
          groups: [
            {'id': _gA, 'name': '5-A', 'grade': 5},
            {'id': _gB, 'name': '5-B', 'grade': 5},
          ],
          students: [
            _student('s1', _gA),
            _student('s2', _gA, language: 'xx'), // junk value -> default too
          ],
        ),
      );
      final (classes, _) = await k.listClasses(_school);
      expect(
        {for (final c in classes) c['class_label']: c['language']},
        {'5-A': 'ru', '5-B': 'ru'},
      ); // empty class -> default
      final (rows, _) = await k.listStudents(_school, '5-A');
      expect(rows.map((r) => r['language']), ['ru', 'ru']);
      expect(rows.map((r) => r['attempt_id']), [
        'offline|s1|$_gA|ru',
        'offline|s2|$_gA|ru',
      ]);
      final start = await k.startAttempt(
        attemptId: rows.first['attempt_id'],
        subject: 'math',
      );
      expect(start['test_key'], 'diag:math:g5:ru:v1');
    },
  );

  test('student language the pack has no diagnostics for falls back', () async {
    final k = await open(
      _pack(
        tests: [_diag('math', 'uz')],
        groups: [
          {'id': _gA, 'name': '5-A', 'grade': 5},
        ],
        students: [_student('s1', _gA, language: 'ru')],
      ),
    );
    final (rows, _) = await k.listStudents(_school, '5-A');
    expect(rows.single['language'], 'uz');
    final start = await k.startAttempt(
      attemptId: rows.single['attempt_id'],
      subject: 'math',
    );
    expect(start['test_key'], 'diag:math:g5:uz:v1');
  });

  test('diagnosticStudentLanguage', () {
    expect(diagnosticStudentLanguage({'language': 'RU'}, 'uz'), 'ru');
    expect(diagnosticStudentLanguage({'language': ' uz '}, 'ru'), 'uz');
    expect(diagnosticStudentLanguage({'language': 'en'}, 'uz'), 'uz');
    expect(diagnosticStudentLanguage({}, 'ru'), 'ru');
    expect(diagnosticStudentLanguage({'language': null}, 'ru'), 'ru');
  });
}
