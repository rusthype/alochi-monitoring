// OfflinePackageApi / OfflineDiagnosticKioskApi / session wiring, driven by
// a pack built in memory (no KDF, no network).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/db/test_cache.dart';
import 'package:alochi_monitoring/core/models/models.dart';
import 'package:alochi_monitoring/core/offline/offline_crypto.dart';
import 'package:alochi_monitoring/core/offline/offline_diagnostic_api.dart';
import 'package:alochi_monitoring/core/offline/offline_media.dart';
import 'package:alochi_monitoring/core/offline/offline_package_api.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/security/incident_log.dart';
import 'package:alochi_monitoring/core/services/test_catalog_service.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _school = '00000000-0000-4000-8000-0000000000b2';
const _g1 = '00000000-0000-4000-8000-0000000000c1';
const _g2 = '00000000-0000-4000-8000-0000000000c2';
const _s1 = '00000000-0000-4000-8000-0000000000d1';
const _s2 = '00000000-0000-4000-8000-0000000000d2';
const _sha = '4161eccd30d857ca5633b1fe7fc1bd5762c6adf526cd3ad54e25421ea2457ee9';

Map<String, dynamic> _test(String key, {List<String> groupIds = const []}) => {
      'type': 'test',
      'key': key,
      'catalog': {
        'title': 'T $key',
        'grade': 5,
        'version': 3,
        'subject': 'english',
        'runner_type': 'engine',
        'school_buttons': [],
        'group_ids': groupIds,
        'max_attempts': 1,
      },
      'data': {
        'test_key': key,
        'title': 'T $key',
        'grade': 5,
        'version': 3,
        'variants': {
          '1': {
            'Vocabulary': [
              {
                'type': 'image_choice',
                'img': 'media/$_sha.jpg',
                'q': 'What?',
                'opts': ['a', 'b']
              }
            ]
          }
        },
      },
    };

Map<String, dynamic> _diag(String subject, int grade, int variant) => {
      'type': 'diagnostic',
      'key': 'diag:$subject:g$grade:uz:v$variant',
      'catalog': {},
      'data': {
        'questions': [
          {
            'id': '$subject-q1',
            'topic': 't',
            'level': 1,
            'question_text': '2+2?',
            'options': ['3', '4', '5', '6'],
            'image': 'media/$_sha.jpg',
            'svg_visual': '',
          },
          {
            'id': '$subject-q2',
            'topic': 't',
            'level': 1,
            'question_text': '1+1?',
            'options': ['2', '3'],
            'image': '',
            'svg_visual': '',
          },
        ]
      },
    };

LoadedPack _pack() => LoadedPack(
      manifest: PackManifest(
        formatVersion: 1,
        packUuid: '00000000-0000-4000-8000-0000000000a1',
        schoolId: _school,
        schoolCode: '999',
        createdAt: DateTime.utc(2026, 1, 1),
        expiresAt: DateTime.utc(2099, 1, 1),
        kdfIter: 1,
        kdfSalt: Uint8List(16),
        files: const {},
      ),
      tests: [
        _test('t_all'),
        _test('t_g1_only', groupIds: [_g1]),
        {
          'type': 'package',
          'key': 'package:42:v1',
          'catalog': {
            'title': 'Pkg',
            'grade': 5,
            'math_count': 1,
            'eng_count': 1
          },
          'data': {
            'questions': [
              {
                'id': 'q1',
                'subject': 'math',
                'position': 1,
                'prompt': 'p',
                'options': ['x', 'y'],
                'image': 'media/$_sha.jpg'
              }
            ]
          },
        },
        _diag('math', 5, 1),
        _diag('english', 5, 1),
      ],
      groups: [
        {'id': _g1, 'name': '5-A | Ingliz', 'grade': 5},
        {'id': _g2, 'name': '6-B', 'grade': null},
      ],
      students: [
        {'id': _s1, 'code': 'A-0001', 'name': 'Valiyev Ali', 'group_id': _g1},
        {
          'id': _s2,
          'code': 'A-0002',
          'name': 'Karimova Zilola',
          'group_id': _g2
        },
        // same student in a second group appears twice with the same id
        {'id': _s1, 'code': 'A-0001', 'name': 'Valiyev Ali', 'group_id': _g2},
      ],
      chainKey: Uint8List.fromList(List.generate(32, (i) => 100 + i)),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late MonitoringApi onlineApi;
  late DiagnosticKioskApi onlineDiag;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('offline_api_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    onlineApi = api;
    onlineDiag = diagnosticKioskApi;
    await OfflinePackSession.open(
        _pack(), Directory(p.join(tmp.path, 'media')));
  });

  tearDown(() async {
    OfflinePackSession.close();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test('open() swaps the global clients and close() restores the same ones',
      () {
    expect(api, isA<OfflinePackageApi>());
    expect(diagnosticKioskApi, isA<OfflineDiagnosticKioskApi>());
    expect(TestCache.isMemoryMode, isTrue);
    expect(OfflineMedia.root, isNotNull);
    expect(OfflinePackSession.isActive, isTrue);

    OfflinePackSession.close();
    expect(identical(api, onlineApi), isTrue);
    expect(identical(diagnosticKioskApi, onlineDiag), isTrue);
    expect(TestCache.isMemoryMode, isFalse);
    expect(OfflineMedia.root, isNull);
    expect(OfflinePackSession.isActive, isFalse);
  });

  group('roster', () {
    test('groups and the student picker come from the pack', () async {
      final groups = await api.fetchGroups('999');
      expect(groups.map((g) => g['name']), ['5-A | Ingliz', '6-B']);
      expect(groups.first['id'], _g1);
      expect(groups.first['display'], '5-A | Ingliz');

      final s = await api.fetchStudents(_g2);
      expect(s.map((e) => e['name']), ['Karimova Zilola', 'Valiyev Ali']);
      // identity is the UUID; the picker must not prefer a printed code
      expect(s.every((e) => !e.containsKey('student_code')), isTrue);
      expect(s.first['id'], _s2);
      expect(s.first['code'], 'A-0002');
      expect(await api.fetchStudents('nope'), isEmpty);
    });
  });

  group('tests', () {
    test('catalog respects group_ids (empty = every group)', () async {
      final forG1 = await api.fetchTestCatalog(groupId: _g1);
      expect(forG1.map((e) => e['test_key']), ['t_all', 't_g1_only']);
      final forG2 = await api.fetchTestCatalog(groupId: _g2);
      expect(forG2.map((e) => e['test_key']), ['t_all']);
      expect(forG1.first['title'], 'T t_all');
      expect(forG1.first['version'], 3);
    });

    test(
        'catalog refresh with a pack open really fills the cache '
        '(no download tap): status cached AND test data resolvable', () async {
      expect(await TestCache.get('t_all'), isNull);
      final entries = await testCatalogService.refresh(groupId: _g1);
      expect(entries, isNotEmpty);
      expect(entries.every((e) => e.status == CatalogStatus.cached), isTrue);
      // what launchRunner reads before opening the engine
      final cached = await TestCache.get('t_all');
      expect(cached, isNotNull);
      expect(cached!['title'], 'T t_all');
      expect(await TestCache.get('t_g1_only'), isNotNull);
    });

    test('fetchTest returns the body; download lands in MEMORY, not sqlite',
        () async {
      final data = await api.fetchTest('t_all');
      expect(data!['test_key'], 't_all');
      expect(jsonEncode(data).contains('"ans"'), isFalse);
      expect(await api.fetchTest('missing'), isNull);

      expect(await testCatalogService.download('t_all'), isTrue);
      final cached = await TestCache.get('t_all');
      expect(cached!['title'], 'T t_all');
      expect(await TestCache.versionOf('t_all'), 3);
      expect((await TestCache.all()).single['test_key'], 't_all');
    });

    test('legacy package questions keep the media ref for local rendering',
        () async {
      final pkgs = await api.getPackages(5);
      expect(pkgs.single.id, '42');
      final qs = await api.getQuestions('42', 1);
      expect(qs.single.image, 'media/$_sha.jpg');
    });

    test('pack image refs resolve to files only while a pack is open', () {
      final f = OfflineMedia.fileFor('media/$_sha.jpg');
      expect(f!.path, p.join(tmp.path, 'media', '$_sha.jpg'));
      expect(OfflineMedia.fileFor('https://x/y.jpg'), isNull);
      expect(OfflineMedia.fileFor('media/../../etc/passwd'), isNull);
      expect(OfflineMedia.fileFor('/media/$_sha.jpg'), isNull);
      OfflinePackSession.close();
      expect(OfflineMedia.fileFor('media/$_sha.jpg'), isNull);
    });
  });

  group('results', () {
    test('local submit appends to the chain with incidents, never the network',
        () async {
      IncidentLog.instance.drain();
      IncidentLog.instance.add('focus_lost', {'state': 'inactive'});
      final r = await api.submitLocalResultFull({
        'student_id': _s1,
        'test_key': 't_all',
        'raw_answers': {'V/0': 1}
      }, 'tok-1');
      expect(r['synced'], true);
      final rows = await PackResultsDb.rowsForPack(
          '00000000-0000-4000-8000-0000000000a1');
      expect(rows, hasLength(1));
      expect(rows.single.idempotencyKey, 'tok-1');
      expect(jsonDecode(rows.single.payloadJson)['student_id'], _s1);
      expect(rows.single.incidents.single['type'], 'focus_lost');
      expect(
          rows.single.hash,
          OfflineCrypto.chainHash(_pack().chainKey, '0' * 64,
              rows.single.payloadJson, rows.single.metaJson));
      // drained into the row
      expect(IncidentLog.instance.snapshot, isEmpty);
    });

    test('legacy package submit also lands in the chain', () async {
      final r = await api.submitResultFull(const TestResult(
          packageId: '42',
          variant: 1,
          mathScore: 0,
          engScore: 0,
          totalPct: 0,
          answers: {'q1': 'x'},
          deviceId: 'd'));
      expect(r['synced'], true);
      final rows = await PackResultsDb.rowsForPack(
          '00000000-0000-4000-8000-0000000000a1');
      expect(jsonDecode(rows.single.payloadJson)['test_key'], 'package:42:v1');
    });

    test('pre-existing online queue rows are never drained into a pack',
        () async {
      await OfflineQueue.enqueueLocal({'x': 1}, 'old-token');
      expect(await api.flushOfflineQueue(), 0);
      expect(await OfflineQueue.pendingLocalCount(), 1);
      expect(await api.ping(), isFalse);
    });

    test('login is unavailable in pack mode', () {
      expect(
          () => api.login('a', 'b'),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'offline_unsupported')
              .having(
                  (e) => e.message.contains('Oflayn'), 'no uz text', false)));
    });
  });

  group('diagnostic', () {
    test('roster, subjects and a fixed-variant start in the runner shape',
        () async {
      final (schools, _) = await diagnosticKioskApi.listSchools();
      expect(schools.single['school_id'], _school);
      final (classes, _) = await diagnosticKioskApi.listClasses(_school);
      expect(classes.map((c) => c['class_label']), ['5-A | Ingliz', '6-B']);
      expect(classes.first['language'], 'uz');
      final (students, _) =
          await diagnosticKioskApi.listStudents(_school, '5-A | Ingliz');
      expect(students.single['student_name'], 'Valiyev Ali');
      final attemptId = students.single['attempt_id'] as String;

      final subj = await diagnosticKioskApi.availableSubjects(5);
      expect(subj['subjects'], ['math', 'english']);

      final start = await diagnosticKioskApi.startAttempt(
          attemptId: attemptId, subject: 'math');
      expect(start['is_fixed_variant'], true);
      expect(start['total_questions'], 2);
      final q = (start['questions'] as List).first as Map;
      expect(q['id'], 'math-q1');
      expect(q['option_a'], '3');
      expect(q['option_b'], '4');
      expect(q['option_d'], '6');
      expect(q['text'], '2+2?');
      expect(q['image_url'], 'media/$_sha.jpg');
      // the pack never carries a correct-answer field
      expect(jsonEncode(start).contains('correct'), isFalse);
    });

    test('finishing each subject chains one {q,a} entry and walks the subjects',
        () async {
      final (students, _) =
          await diagnosticKioskApi.listStudents(_school, '5-A | Ingliz');
      final attemptId = students.single['attempt_id'] as String;

      final r1 = await diagnosticKioskApi
          .finishAttempt(attemptId: attemptId, answers: [
        {'question_id': 'math-q1', 'selected': 'B'},
        {'question_id': 'math-q2', 'selected': 'A'},
      ]);
      expect(r1['next_subject'], 'english');
      expect(r1.containsKey('score_math'), isFalse);

      final r2 = await diagnosticKioskApi
          .finishAttempt(attemptId: attemptId, answers: [
        {'question_id': 'english-q1', 'selected': 'C'}
      ]);
      expect(r2['next_subject'], '');

      // a second finish of the same subject is a numbered RETAKE, not lost
      await diagnosticKioskApi.finishAttempt(attemptId: attemptId, answers: [
        {'question_id': 'math-q1', 'selected': 'B'}
      ]);

      final rows = await PackResultsDb.rowsForPack(
          '00000000-0000-4000-8000-0000000000a1');
      expect(rows, hasLength(3));
      final keys = rows.map((r) => r.idempotencyKey).toList();
      expect(keys.toSet(), hasLength(3));
      expect(keys.every((k) => k.length <= 64), isTrue);
      // rows: math #1, english #1, math #2 (retake) -- same prefix, next ordinal
      expect(keys[0].endsWith(':1'), isTrue);
      expect(keys[2].endsWith(':2'), isTrue);
      expect(keys[2].substring(0, keys[2].length - 1),
          keys[0].substring(0, keys[0].length - 1));
      expect(keys[1], isNot(keys[0]));
      final first = jsonDecode(rows.first.payloadJson) as Map;
      expect(first['test_key'], 'diag:math:g5:uz:v1');
      expect(first['student_id'], _s1);
      expect(first['group_id'], _g1);
      expect(first['answers'], [
        {'q': 'math-q1', 'a': 'B'},
        {'q': 'math-q2', 'a': 'A'},
      ]);
      expect(rows.first.idempotencyKey.length, lessThanOrEqualTo(64));
    });

    test('an unknown attempt id is a 404, not a crash', () {
      expect(
          () => diagnosticKioskApi.startAttempt(
              attemptId: 'bogus', subject: 'math'),
          throwsA(isA<ApiException>()));
    });
  });
}
