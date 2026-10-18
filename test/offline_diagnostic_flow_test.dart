// Diagnostic tests on a USB pack, roster -> finished: every call goes to the
// pack adapter (zero calls on the parked online api), each subject becomes
// exactly one `diag:...` chain entry with A-D answers, nothing is left for the
// real server to be re-sent later, and the finished screen needs no score.
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

const _school = '00000000-0000-4000-8000-0000000000b2';
const _g1 = '00000000-0000-4000-8000-0000000000c1';
const _s1 = '00000000-0000-4000-8000-0000000000d1';
const _packUuid = '00000000-0000-4000-8000-0000000000a1';
const _sha = '4161eccd30d857ca5633b1fe7fc1bd5762c6adf526cd3ad54e25421ea2457ee9';

Map<String, dynamic> _diag(String subject) => {
      'type': 'diagnostic',
      'key': 'diag:$subject:g5:uz:v1',
      'catalog': {},
      'data': {
        'questions': [
          {
            'id': '$subject-q1',
            'topic': 't',
            'level': 1,
            'question_text': 'Q1',
            'options': ['a', 'b', 'c', 'd'],
            'image': 'media/$_sha.jpg',
            'svg_visual': '',
          },
          {
            'id': '$subject-q2',
            'topic': 't',
            'level': 1,
            'question_text': 'Q2',
            'options': ['a', 'b', 'c', 'd'],
            'image': '',
            'svg_visual': '',
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
      ],
      chainKey: Uint8List.fromList(List.generate(32, (i) => 100 + i)),
    );

/// The real online kiosk client, parked behind the pack: any call is a leak.
class _RecordingOnlineDiag extends DiagnosticKioskApi {
  final calls = <String>[];
  Never _hit(String n) {
    calls.add(n);
    throw StateError('online diagnostic api reached: $n');
  }

  @override
  Future<(List<Map<String, dynamic>>, bool)> listSchools() async =>
      _hit('listSchools');
  @override
  Future<(List<Map<String, dynamic>>, bool)> listClasses(String s) async =>
      _hit('listClasses');
  @override
  Future<(List<Map<String, dynamic>>, bool)> listStudents(
          String s, String c) async =>
      _hit('listStudents');
  @override
  Future<Map<String, dynamic>> availableSubjects(int grade,
          {String language = 'uz'}) async =>
      _hit('availableSubjects');
  @override
  Future<Map<String, dynamic>> peekSubject(
          {required String attemptId, required String subject}) async =>
      _hit('peekSubject');
  @override
  Future<Map<String, dynamic>> startAttempt(
          {required String attemptId, required String subject}) async =>
      _hit('startAttempt');
  @override
  Future<Map<String, dynamic>> submitAnswer(
          {required String attemptId,
          required String questionId,
          required String selected}) async =>
      _hit('submitAnswer');
  @override
  Future<Map<String, dynamic>> pingElapsed(
          {required String attemptId, required int elapsedSeconds}) async =>
      _hit('pingElapsed');
  @override
  Future<Map<String, dynamic>> syncAnswers(
          {required String attemptId,
          required List<Map<String, dynamic>> answers,
          int? generation}) async =>
      _hit('syncAnswers');
  @override
  Future<Map<String, dynamic>> finishAttempt(
          {required String attemptId,
          required List<Map<String, dynamic>> answers,
          List<String>? flaggedQuestionIds,
          int? generation}) async =>
      _hit('finishAttempt');
  @override
  Future<Map<String, dynamic>> submitFinishOffline(
          Map<String, dynamic> payload, String token,
          {String subject = ''}) async =>
      _hit('submitFinishOffline');
  @override
  Future<String> webTestStart(
          {required String attemptId, required String testKey}) async =>
      _hit('webTestStart');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late _RecordingOnlineDiag online;
  late DiagnosticKioskApi saved;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('offline_diag_flow_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    await DiagnosticAnswerStore.openInMemory();
    saved = diagnosticKioskApi;
    online = _RecordingOnlineDiag();
    diagnosticKioskApi = online;
    await OfflinePackSession.open(
        _pack(), Directory(p.join(tmp.path, 'media')));
  });

  tearDown(() async {
    OfflinePackSession.close();
    diagnosticKioskApi = saved;
    await DiagnosticAnswerStore.reset();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test('roster to finish: one diag chain entry per subject, no online call',
      () async {
    expect(diagnosticKioskApi, isA<OfflineDiagnosticKioskApi>());
    final k = diagnosticKioskApi;

    final (schools, _) = await k.listSchools();
    final (classes, _) = await k.listClasses(schools.single['school_id']);
    final label = classes.single['class_label'] as String;
    final (students, _) = await k.listStudents(_school, label);
    final attemptId = students.single['attempt_id'] as String;
    final subjects = (await k.availableSubjects(5))['subjects'] as List;
    expect(subjects, ['math', 'english']);

    final answers = <String, List<String>>{
      'math': ['D', 'A'],
      'english': ['C', 'B'],
    };
    for (var i = 0; i < subjects.length; i++) {
      final subject = subjects[i] as String;
      // roster tap: peek must look like a ready package, not "online only"
      final peek = await k.peekSubject(attemptId: attemptId, subject: subject);
      expect(peek['fixed_variant'], isTrue);
      final start =
          await k.startAttempt(attemptId: attemptId, subject: subject);
      final qs = (start['questions'] as List).cast<Map>();
      expect(qs, hasLength(2));

      // what the runner autosaves while the student taps
      for (var n = 0; n < qs.length; n++) {
        await DiagnosticAnswerStore.saveAnswer(
          attemptId: attemptId,
          subject: subject,
          questionIndex: n + 1,
          questionId: qs[n]['id'] as String,
          selectedOption: answers[subject]![n],
        );
      }
      expect(await DiagnosticAnswerStore.attemptsWithPending(), [attemptId]);

      final resp = await k.finishAttempt(attemptId: attemptId, answers: [
        for (var n = 0; n < qs.length; n++)
          {'question_id': qs[n]['id'], 'selected': answers[subject]![n]},
      ]);
      // server-only scoring: no score fields at all
      expect(resp.keys.where((e) => e.startsWith('score_')), isEmpty);
      expect(resp['next_subject'], i == 0 ? 'english' : '');
      // nothing left for the real server to be re-sent later
      expect(await DiagnosticAnswerStore.attemptsWithPending(), isEmpty);
    }

    final rows = await PackResultsDb.rowsForPack(_packUuid);
    expect(rows, hasLength(2));
    final payloads = rows.map((r) => jsonDecode(r.payloadJson) as Map).toList();
    expect(payloads.map((e) => e['test_key']),
        ['diag:math:g5:uz:v1', 'diag:english:g5:uz:v1']);
    expect(payloads[0]['answers'], [
      {'q': 'math-q1', 'a': 'D'},
      {'q': 'math-q2', 'a': 'A'},
    ]);
    expect(payloads[1]['answers'], [
      {'q': 'english-q1', 'a': 'C'},
      {'q': 'english-q2', 'a': 'B'},
    ]);
    expect(payloads.every((e) => e['student_id'] == _s1), isTrue);

    expect(online.calls, isEmpty);
  });
}
