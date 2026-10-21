// "Bola qo'shish" inside an offline pack (add-student wave 2-D): a child added
// on this computer is local to the open pack, tests immediately, and its chain
// entries carry `student_id: new:<uuid>` + a `new_student` block.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/models/add_student.dart';
import 'package:alochi_monitoring/core/offline/export_format.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/offline/results_exporter.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _packUuid = '00000000-0000-4000-8000-0000000000a1';
const _school = '00000000-0000-4000-8000-0000000000b2';
const _gA = '00000000-0000-4000-8000-0000000000c1';
const _gB = '00000000-0000-4000-8000-0000000000c2';
const _fixtures = 'test/fixtures/offline';
const _defaultBackend =
    '/Users/max/PycharmProjects/AlochiSchool/alochi/.claude/worktrees/agent-ab638607e6e37ee92/alochi_backend';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

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

final _roster = <Map<String, dynamic>>[
  {'id': 's1', 'code': 'C1', 'name': 'Valiyev Ali', 'group_id': _gA},
  {'id': 's2', 'code': 'C2', 'name': 'Karimova Dilnoza', 'group_id': _gA},
  {'id': 's3', 'code': 'C3', 'name': 'Rahimov Sardor', 'group_id': _gB},
];

LoadedPack _pack({
  String uuid = _packUuid,
  Uint8List? chainKey,
  PackManifest? manifest,
  bool bothLangs = false,
}) =>
    LoadedPack(
      manifest: manifest ??
          PackManifest(
            formatVersion: 1,
            packUuid: uuid,
            schoolId: _school,
            schoolCode: '999',
            createdAt: DateTime.utc(2026, 1, 1),
            expiresAt: DateTime.utc(2099, 1, 1),
            kdfIter: 1,
            kdfSalt: Uint8List(16),
            files: const {},
          ),
      tests: [
        for (final l in bothLangs ? ['uz', 'ru'] : ['uz'])
          for (final s in ['math', 'english']) _diag(s, l),
      ],
      groups: [
        {'id': _gA, 'name': '5-A', 'grade': 5},
        {'id': _gB, 'name': '5-B', 'grade': 5},
      ],
      students: _roster,
      chainKey:
          chainKey ?? Uint8List.fromList(List.generate(32, (i) => 100 + i)),
    );

AddStudentDraft _draft(String first, String last,
        {String? id, DateTime? birth, String parentFio = ''}) =>
    AddStudentDraft(
      firstName: first,
      lastName: last,
      clientTempId: id ?? AddStudentDraft.newTempId(),
      birthDate: birth,
      parentFio: parentFio,
    );

Future<List<Map<String, dynamic>>> _chain(String uuid) async => [
      for (final r in await PackResultsDb.rowsForPack(uuid))
        jsonDecode(r.payloadJson) as Map<String, dynamic>
    ];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late DiagnosticKioskApi savedDiag;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('offline_add_student_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    await DiagnosticAnswerStore.openInMemory();
    savedDiag = diagnosticKioskApi;
  });

  tearDown(() async {
    OfflinePackSession.close();
    diagnosticKioskApi = savedDiag;
    await DiagnosticAnswerStore.reset();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<OfflinePackSession> open([LoadedPack? pack]) =>
      OfflinePackSession.open(
          pack ?? _pack(), Directory(p.join(tmp.path, 'media')));

  group('duplicate check', () {
    test('a name in a PARALLEL class asks "Bu shumi?" (any word order)',
        () async {
      await open();
      // 5-B's "Rahimov Sardor" typed into 5-A, first/last swapped.
      await expectLater(
        api.addStudent(groupId: _gA, draft: _draft('Rahimov', 'Sardor')),
        throwsA(isA<SimilarStudentsException>().having(
            (e) => e.candidates.single,
            'candidate',
            isA<SimilarStudent>()
                .having((c) => c.id, 'id', 's3')
                .having((c) => c.groupName, 'group', '5-B')
                .having((c) => c.grade, 'grade', 5))),
      );
      // Cyrillic spelling of a roster name is the same child.
      await expectLater(
        api.addStudent(groupId: _gA, draft: _draft('Али', 'Валиев')),
        throwsA(isA<SimilarStudentsException>()),
      );
      expect(OfflinePackSession.current!.localStudents, isEmpty);
    });

    test('confirmNew creates it; a later twin matches the local child too',
        () async {
      await open();
      final r = await api.addStudent(
          groupId: _gA, draft: _draft('Sardor', 'Rahimov'), confirmNew: true);
      expect(r.id, startsWith('new:'));
      expect(r.groupId, _gA);
      expect(r.grade, 5);

      await expectLater(
        api.addStudent(groupId: _gB, draft: _draft('Sardor', 'Rahimov')),
        throwsA(isA<SimilarStudentsException>().having(
            (e) => e.candidates.map((c) => c.id).toSet(), 'ids', {'s3', r.id})),
      );
    });

    test('a different name needs no confirmation; same temp id is idempotent',
        () async {
      await open();
      final d = _draft('Nodira', 'Yusupova');
      final a = await api.addStudent(groupId: _gA, draft: d);
      final b = await api.addStudent(groupId: _gA, draft: d);
      expect(b.id, a.id);
      expect(OfflinePackSession.current!.localStudents, hasLength(1));
    });

    test('unknown group / bad name are refused', () async {
      await open();
      await expectLater(
          api.addStudent(groupId: 'nope', draft: _draft('Nodira', 'Yusupova')),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'invalid_group')));
      await expectLater(
          api.addStudent(groupId: _gA, draft: _draft('N', 'Yusupova')),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'invalid_name')));
    });
  });

  group('roster + persistence', () {
    test('fetchStudents shows the child (pending) only in its own group',
        () async {
      await open();
      final r = await api.addStudent(
          groupId: _gA, draft: _draft('Nodira', 'Yusupova'));
      final inA = await api.fetchStudents(_gA);
      final kid = inA.singleWhere((s) => s['id'] == r.id);
      expect(kid['pending'], true);
      expect(kid['name'], 'Yusupova Nodira');
      expect(kid['group_id'], _gA);
      expect(inA.map((s) => s['id']), containsAll(['s1', 's2', r.id]));
      expect((await api.fetchStudents(_gB)).map((s) => s['id']), ['s3']);
      // The hub serves its LAN clients the signed roster only.
      final hubView =
          await (api as dynamic).fetchStudents(_gA, includeLocal: false)
              as List<Map<String, dynamic>>;
      expect(hubView.map((s) => s['id']), ['s1', 's2']);
      // The signed pack roster itself is untouched.
      expect(OfflinePackSession.current!.pack.students, hasLength(3));
    });

    test('survives close/re-open of the same pack, not another pack', () async {
      await open();
      final d = _draft('Nodira', 'Yusupova',
          birth: DateTime(2015, 3, 9), parentFio: 'Yusupov Anvar');
      final r = await api.addStudent(groupId: _gA, draft: d);
      OfflinePackSession.close();

      await open();
      final back =
          (await api.fetchStudents(_gA)).singleWhere((s) => s['id'] == r.id);
      expect(back['name'], 'Yusupova Nodira');
      expect(back['birth_date'], '2015-03-09');
      expect(back['parent_fio'], 'Yusupov Anvar');
      OfflinePackSession.close();

      await open(_pack(uuid: '00000000-0000-4000-8000-0000000000ff'));
      expect(OfflinePackSession.current!.localStudents, isEmpty);
    });

    test('row body is encrypted at rest', () async {
      await open();
      await api.addStudent(groupId: _gA, draft: _draft('Nodira', 'Yusupova'));
      final db = await OfflineQueue.db;
      final raw = (await db.query('pack_local_students')).single['data'];
      expect(raw.toString(), isNot(contains('Yusupova')));
    });
  });

  group('monitoring chain entry', () {
    test('new:<uuid> result carries new_student exactly per contract',
        () async {
      await open();
      final d = _draft('Nodira', 'Yusupova',
          birth: DateTime(2015, 3, 9), parentFio: 'Yusupov Anvar');
      await api.addStudent(groupId: _gA, draft: d);

      final res = await api.submitLocalResultFull({
        'name': 'Yusupova Nodira',
        'student_id': d.clientTempId,
        'group_id': _gA,
        'test_key': 'golden_test_1',
        'raw_answers': {'a': 1},
        'detail': {'test_key': 'golden_test_1'},
      }, 'mw-0123456789abcdef0123456789abcdef01234567');
      expect(res['synced'], true);

      final rows = await PackResultsDb.rowsForPack(_packUuid);
      final payload = jsonDecode(rows.single.payloadJson) as Map;
      expect(payload['student_id'], d.clientTempId);
      expect(payload['new_student'], {
        'temp_id': d.clientTempId,
        'first_name': 'Nodira',
        'last_name': 'Yusupova',
        'birth_date': '2015-03-09',
        'parent_fio': 'Yusupov Anvar',
        'group_id': _gA,
      });
      // ignore: avoid_print
      print('chain entry payload_json: ${rows.single.payloadJson}');
      // meta/idempotency key stays within the server's 64-char rule
      expect(PackResultsDb.isValidKey(rows.single.idempotencyKey), true);
      expect(rows.single.idempotencyKey.length, lessThan(64));
      // the roster marks the child as done for that test
      expect(
          await OfflinePackSession.current!.finishedStudentIds('golden_test_1'),
          {d.clientTempId});
    });

    test('optional fields are omitted, not null', () async {
      await open();
      final d = _draft('Nodira', 'Yusupova');
      await api.addStudent(groupId: _gA, draft: d);
      await api.submitLocalResultFull(
          {'student_id': d.clientTempId, 'group_id': _gA}, 'tok-1');
      final nsBlock = (await _chain(_packUuid)).single['new_student'] as Map;
      expect(nsBlock.keys.toSet(),
          {'temp_id', 'first_name', 'last_name', 'group_id'});
    });

    test('REGRESSION: a pack student\'s payload is stored byte-for-byte',
        () async {
      await open();
      // a local child exists, to prove it does not leak into other payloads
      await api.addStudent(groupId: _gA, draft: _draft('Nodira', 'Yusupova'));
      final payload = <String, dynamic>{
        'name': 'Valiyev Ali',
        'student_id': 's1',
        'group_id': _gA,
        'test_key': 'golden_test_1',
        'raw_answers': {'Vocabulary/0': 1},
        'detail': {'test_key': 'golden_test_1'},
      };
      await api.submitLocalResultFull(payload, 'tok-regress');
      final rows = await PackResultsDb.rowsForPack(_packUuid);
      expect(rows.single.payloadJson, jsonEncode(payload));
      expect(rows.single.payloadJson, isNot(contains('new_student')));
    });

    test('the exporter writes the entry verbatim (payload_json carries it)',
        () async {
      await open();
      final d = _draft('Nodira', 'Yusupova');
      await api.addStudent(groupId: _gA, draft: d);
      await api.submitLocalResultFull(
          {'student_id': d.clientTempId, 'group_id': _gA}, 'tok-exp');
      final row = (await PackResultsDb.rowsForPack(_packUuid)).single;
      final entry = exportEntry(
          prevHash: row.prevHash,
          hash: row.hash,
          payloadJson: row.payloadJson,
          metaJson: row.metaJson);
      expect(jsonDecode(entry['payload_json']!)['new_student']['temp_id'],
          d.clientTempId);
      expect(entry.keys.toSet(),
          {'prev_hash', 'hash', 'payload_json', 'meta_json'});
    });
  });

  group('diagnostic offline', () {
    Future<DiagnosticKioskApi> openDiag() async {
      await open();
      expect(diagnosticKioskApi, isA<DiagnosticKioskApi>());
      return diagnosticKioskApi;
    }

    test('addStudent -> attempt_id offline|new:<uuid>|<gid>|<lang>, listed',
        () async {
      final k = await openDiag();
      final d = _draft('Nodira', 'Yusupova');
      final r = await k.addStudent(
          schoolId: _school, classLabel: '5-A', language: 'uz', draft: d);
      expect(r.id, 'offline|${d.clientTempId}|$_gA|uz');
      expect(r.status, 'not_started');

      final (rows, _) = await k.listStudents(_school, '5-A');
      final row = rows.singleWhere((x) => x['attempt_id'] == r.id);
      expect(row['pending'], true);
      expect(row['student_name'], 'Yusupova Nodira');
      expect(row['language'], 'uz');
      expect(row['next_subject'], 'math');
      // pack students are unchanged (no pending key)
      expect(
          rows
              .firstWhere((x) => x['student_name'] == 'Valiyev Ali')
              .containsKey('pending'),
          false);
      // not in the other class
      expect((await k.listStudents(_school, '5-B')).$1, hasLength(1));
    });

    test('duplicate across the parallel class is caught, name order free',
        () async {
      final k = await openDiag();
      await expectLater(
          k.addStudent(
              schoolId: _school,
              classLabel: '5-A',
              language: 'uz',
              draft: _draft('Rahimov', 'Sardor')),
          throwsA(isA<SimilarStudentsException>()));
    });

    test('finishAttempt entry has student_id + new_student; key < 64',
        () async {
      final k = await openDiag();
      final d = _draft('Nodira', 'Yusupova', birth: DateTime(2015, 3, 9));
      final r = await k.addStudent(
          schoolId: _school, classLabel: '5-A', language: 'uz', draft: d);

      // _stableHash(temp id) picks a variant; start works for the temp id
      final start = await k.startAttempt(attemptId: r.id, subject: 'math');
      expect(start['test_key'], 'diag:math:g5:uz:v1');

      await k.finishAttempt(attemptId: r.id, answers: [
        {'question_id': 'math-uz-q1', 'selected': 'B'},
      ]);
      final rows = await PackResultsDb.rowsForPack(_packUuid);
      final payload = jsonDecode(rows.single.payloadJson) as Map;
      expect(payload['student_id'], d.clientTempId);
      expect(payload['group_id'], _gA);
      expect(payload['name'], 'Yusupova Nodira');
      expect(payload['new_student'], {
        'temp_id': d.clientTempId,
        'first_name': 'Nodira',
        'last_name': 'Yusupova',
        'birth_date': '2015-03-09',
        'group_id': _gA,
      });
      expect(rows.single.idempotencyKey.length, lessThan(64));

      // roster now shows the subject as done -> next is english
      final (after, _) = await k.listStudents(_school, '5-A');
      final row = after.singleWhere((x) => x['attempt_id'] == r.id);
      expect(row['status'], 'partial');
      expect(row['next_subject'], 'english');
    });

    test('REGRESSION: a pack student diagnostic entry has no new_student',
        () async {
      final k = await openDiag();
      await k.addStudent(
          schoolId: _school,
          classLabel: '5-A',
          language: 'uz',
          draft: _draft('Nodira', 'Yusupova'));
      await k.finishAttempt(attemptId: 'offline|s1|$_gA|uz', answers: [
        {'question_id': 'math-uz-q1', 'selected': 'A'},
      ]);
      final payload = (await _chain(_packUuid)).single;
      expect(payload['student_id'], 's1');
      expect(payload.containsKey('new_student'), false);
    });

    test('class language majority counts the added children', () async {
      await open(_pack(bothLangs: true));
      final k = diagnosticKioskApi;
      // roster rows carry no language -> pack default (uz): 5-A is uz
      final (before, _) = await k.listClasses(_school);
      expect({for (final c in before) c['class_label']: c['language']},
          {'5-A': 'uz', '5-B': 'uz'});
      // two ru children join 5-A (2 uz pack students) -> tie stays uz ...
      for (final n in ['Yusupova', 'Orlova']) {
        final r = await k.addStudent(
            schoolId: _school,
            classLabel: '5-A',
            language: 'ru',
            draft: _draft('Nodira', n));
        expect(r.id, endsWith('|ru'));
      }
      expect(
          (await k.listClasses(_school))
              .$1
              .firstWhere((c) => c['class_label'] == '5-A')['language'],
          'uz');
      // ... a third makes ru the majority (3 of 5)
      await k.addStudent(
          schoolId: _school,
          classLabel: '5-A',
          language: 'ru',
          draft: _draft('Nodira', 'Petrova'));
      expect(
          (await k.listClasses(_school))
              .$1
              .firstWhere((c) => c['class_label'] == '5-A')['language'],
          'ru');
      // the ru child is served the ru test
      final (rows, _) = await k.listStudents(_school, '5-A');
      final ru = rows.firstWhere((x) => x['student_name'] == 'Orlova Nodira');
      expect(
          (await k.startAttempt(
              attemptId: ru['attempt_id'], subject: 'math'))['test_key'],
          'diag:math:g5:ru:v1');
    });
  });

  group('.alochires export', () {
    final backendDir =
        Platform.environment['ALOCHI_BACKEND_DIR'] ?? _defaultBackend;
    final script = p.join(backendDir,
        'apps/monitoring/tests/fixtures/offline/verify_alochires.py');
    final canVerify = File(script).existsSync() &&
        (() {
          try {
            return Process.runSync(
                    'python3', ['-I', '-c', 'import cryptography']).exitCode ==
                0;
          } catch (_) {
            return false;
          }
        })();

    test('backend reader verifies the chain and sees new_student', () async {
      final keys = OfflineKeys(
        signingPem:
            File('$_fixtures/test_signing_public.pem').readAsStringSync(),
        resultsPem:
            File('$_fixtures/test_results_public.pem').readAsStringSync(),
      );
      final golden = await PackLoader(keys: keys).open(
          File('$_fixtures/golden.alochipack').readAsBytesSync(), '12345678');
      // The golden pack's own key/uuid (so the python reader can verify the
      // HMAC chain) with our roster.
      final pack = LoadedPack(
        manifest: golden.manifest,
        tests: golden.tests,
        groups: [
          {'id': _gA, 'name': '5-A', 'grade': 5},
        ],
        students: [_roster.first],
        chainKey: golden.chainKey,
      );
      await open(pack);
      final d = _draft('Nodira', 'Yusupova',
          birth: DateTime(2015, 3, 9), parentFio: 'Yusupov Anvar');
      await api.addStudent(groupId: _gA, draft: d);
      await api.submitLocalResultFull(
          {'student_id': d.clientTempId, 'group_id': _gA, 'name': 'x'},
          'tok-new');
      await api.submitLocalResultFull(
          {'student_id': 's1', 'group_id': _gA, 'name': 'Valiyev Ali'},
          'tok-old');

      final out = await ResultsExporter(
        keys: keys,
        clock: MonitoredClock(
            ticks: () => 1,
            wall: () =>
                DateTime.utc(2026, 10, 17, 9, 30, 15).millisecondsSinceEpoch,
            highWaterStore: _MemHwm()),
        machineId: () async => 'M',
        mac: () async => 'AA',
      ).exportPack(pack.packUuid, tmp, schoolCode: '999');
      expect(out.count, 2);
      expect(out.invalidKeyCount, 0);

      final r = await Process.run('python3', [
        '-I',
        script,
        out.file.path,
        p.join(backendDir,
            'apps/monitoring/tests/fixtures/offline/test_results_private.pem'),
        '12345678',
        '--pack',
        '$_fixtures/golden.alochipack',
      ]);
      expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
      final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
      expect(j['chain_verified'], true);
      final entries = (j['entries'] as List).cast<Map<String, dynamic>>();
      final fresh = entries.firstWhere(
          (e) => e['idempotency_key'] == 'tok-new')['payload'] as Map;
      expect((fresh['new_student'] as Map)['temp_id'], d.clientTempId);
      expect(fresh['student_id'], d.clientTempId);
      final old = entries.firstWhere(
          (e) => e['idempotency_key'] == 'tok-old')['payload'] as Map;
      expect(old.containsKey('new_student'), false);
    },
        skip: canVerify
            ? null
            : 'python3+cryptography and the backend checkout (ALOCHI_BACKEND_DIR) are required');
  });
}
