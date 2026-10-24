// The diagnostic roster derives status/next_subject for a whole class with ONE
// chain lookup (not one awaited query per student x subject) and parses the
// pack's diagnostics once; the rows themselves must not change.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/models/add_student.dart';
import 'package:alochi_monitoring/core/offline/offline_content_source.dart';
import 'package:alochi_monitoring/core/offline/offline_crypto.dart';
import 'package:alochi_monitoring/core/offline/offline_diagnostic_api.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _packUuid = '00000000-0000-4000-8000-0000000000a1';
const _school = '00000000-0000-4000-8000-0000000000b2';

/// Delegates to the real session, counts the chain lookups, and lets a test
/// swap the diagnostics list / add pending local students.
class _Spy implements OfflineContentSource {
  final OfflinePackSession s;
  _Spy(this.s);
  int hasAttemptCalls = 0;
  int batchCalls = 0;
  List<Map<String, dynamic>>? diagOverride;
  List<Map<String, dynamic>> local = const [];

  @override
  String get packUuid => s.packUuid;
  @override
  String get schoolId => s.schoolId;
  @override
  String get schoolCode => s.schoolCode;
  @override
  List<Map<String, dynamic>> get groups => s.groups;
  @override
  List<Map<String, dynamic>> get students => s.students;
  @override
  List<Map<String, dynamic>> get localStudents => local;
  @override
  Future<AddStudentResult> addLocalStudent(
          {required String groupId,
          required AddStudentDraft draft,
          bool confirmNew = false,
          String language = ''}) =>
      throw UnimplementedError();
  @override
  List<Map<String, dynamic>> testsOfType(String type) =>
      type == 'diagnostic' && diagOverride != null
          ? diagOverride!
          : s.testsOfType(type);
  @override
  Future<int> nextAttemptOrdinal(String k) => s.nextAttemptOrdinal(k);
  @override
  Future<bool> hasAttempt(String k) {
    hasAttemptCalls++;
    return s.hasAttempt(k);
  }

  @override
  Future<Set<String>> attemptedPrefixes(Iterable<String> k) {
    batchCalls++;
    return s.attemptedPrefixes(k);
  }

  @override
  Future<void> recordResult(Map<String, dynamic> payload, {String? token}) =>
      s.recordResult(payload, token: token);
  @override
  Future<void> prepareMedia(Object? data) async {}
}

Map<String, dynamic> _diag(String subject, int grade, String lang) => {
      'type': 'diagnostic',
      'key': 'diag:$subject:g$grade:$lang:v1',
      'catalog': {},
      'data': {
        'questions': [
          {
            'id': '$subject-$grade-$lang-q1',
            'topic': 't',
            'level': 1,
            'question_text': 'Q',
            'options': ['a', 'b', 'c', 'd'],
            'image': '',
            'svg_visual': '',
          },
        ],
      },
    };

String _prefix(String sid, String gid, String sub) =>
    'diag:${OfflineCrypto.sha256Hex(utf8.encode('$_packUuid|$sid|$gid|$sub')).substring(0, 24)}:';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('offline_diag_batch_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    await DiagnosticAnswerStore.openInMemory();
  });

  tearDown(() async {
    OfflinePackSession.close();
    await DiagnosticAnswerStore.reset();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test('listStudents: same rows as before, one chain lookup per call',
      () async {
    final key = Uint8List.fromList(List.generate(32, (i) => 100 + i));
    final pack = LoadedPack(
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
      tests: [
        _diag('math', 5, 'uz'),
        _diag('english', 5, 'uz'),
        _diag('math', 4, 'uz'), // grade 4 has no english
        _diag('math', 5, 'ru'),
        _diag('english', 5, 'ru'),
      ],
      groups: [
        {'id': 'gA', 'name': '5-A', 'grade': 5},
        {'id': 'gB', 'name': '4-B', 'grade': 4},
      ],
      students: [
        {'id': 's1', 'name': 'None', 'group_id': 'gA'},
        {'id': 's2', 'name': 'MathOnly', 'group_id': 'gA'},
        {'id': 's3', 'name': 'Both', 'group_id': 'gA', 'language': 'ru'},
        {'id': 's4', 'name': 'Other class', 'group_id': 'gB'},
        {'id': 's5', 'name': 'G4 done', 'group_id': 'gB'},
      ],
      chainKey: key,
    );
    final session = await OfflinePackSession.open(
        pack, Directory(p.join(tmp.path, 'media')));
    Future<void> done(String sid, String gid, String sub) =>
        PackResultsDb.append(
            packUuid: _packUuid,
            chainKey: key,
            idempotencyKey: '${_prefix(sid, gid, sub)}1',
            payloadJson: '{}');
    await done('s2', 'gA', 'math');
    await done('s3', 'gA', 'math');
    await done('s3', 'gA', 'english');
    await done('s5', 'gB', 'math');

    final spy = _Spy(session)
      ..local = [
        {
          'id': 'new:1',
          'name': 'Pending',
          'group_id': 'gA',
          'pending': true,
        }
      ];
    final k = OfflineDiagnosticKioskApi(spy);

    final (a, _) = await k.listStudents(_school, '5-A');
    List<Object?> row(Map<String, dynamic> r) =>
        [r['student_name'], r['status'], r['next_subject'], r['language']];
    expect(a.map(row).toList(), [
      ['None', 'not_started', 'math', 'uz'],
      ['MathOnly', 'partial', 'english', 'uz'],
      ['Both', 'completed', '', 'ru'],
      ['Pending', 'not_started', 'math', 'uz'],
    ]);
    expect(a.map((r) => r['pending']).toList(), [null, null, null, true]);
    expect(a.first['attempt_id'], 'offline|s1|gA|uz');
    expect(a.first['class_label'], '5-A');
    // one batched lookup for 4 students x 2 subjects, no per-prefix queries
    expect(spy.batchCalls, 1);
    expect(spy.hasAttemptCalls, 0);

    final (b, _) = await k.listStudents(_school, '4-B');
    expect(b.map(row).toList(), [
      ['Other class', 'not_started', 'math', 'uz'],
      ['G4 done', 'completed', '', 'uz'],
    ]);
    expect(spy.batchCalls, 2);

    final (classes, _) = await k.listClasses(_school);
    expect(classes, [
      {'class_label': '5-A', 'language': 'uz'},
      {'class_label': '4-B', 'language': 'uz'},
    ]);
  });

  test('parsed diagnostics are refreshed when the source swaps its list',
      () async {
    final key = Uint8List.fromList(List.generate(32, (i) => 100 + i));
    final pack = LoadedPack(
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
      tests: [_diag('math', 5, 'uz')],
      groups: const [],
      students: const [],
      chainKey: key,
    );
    final session = await OfflinePackSession.open(
        pack, Directory(p.join(tmp.path, 'media')));
    final spy = _Spy(session);
    final k = OfflineDiagnosticKioskApi(spy);
    expect((await k.availableSubjects(5))['subjects'], ['math']);
    spy.diagOverride = [_diag('math', 5, 'uz'), _diag('english', 5, 'uz')];
    expect((await k.availableSubjects(5))['subjects'], ['math', 'english']);
  });
}
