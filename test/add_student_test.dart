// "Bola qo'shish": models/validation, the api response classification, the
// local add_student queue kind (+ temp -> server id re-pointing of results
// queued meanwhile) and the v9 local_students table.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/local_students_db.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/models/add_student.dart';
import 'package:alochi_monitoring/core/services/add_student_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

http.Response _json(int status, Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

class _FakeApi extends MonitoringApi {
  final List<Object> addCalls = [];
  final List<Map<String, dynamic>> submitted = [];
  Object? addError;
  String serverId = 'srv-1';

  @override
  Future<AddStudentResult> addStudent({
    required String groupId,
    required AddStudentDraft draft,
    bool confirmNew = false,
  }) async {
    addCalls.add((groupId, draft.clientTempId, confirmNew));
    final err = addError;
    if (err != null) throw err;
    return AddStudentResult(
        id: serverId,
        name: '${draft.lastName} ${draft.firstName}',
        firstName: draft.firstName,
        lastName: draft.lastName,
        groupId: groupId);
  }

  @override
  Future<Map<String, dynamic>> submitLocalResultFull(
      Map<String, dynamic> payload, String token) async {
    submitted.add(payload);
    return {'synced': true};
  }
}

AddStudentDraft _draft([String id = 'new:abc']) => AddStudentDraft(
    firstName: 'Ali',
    lastName: 'Valiyev',
    birthDate: DateTime(2015, 3, 4),
    parentFio: 'Valiyev Karim',
    clientTempId: id);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  group('validateStudentName', () {
    test('accepts latin, cyrillic, apostrophes, hyphen, spaces', () {
      for (final ok in [
        "Ali",
        "G'ulom",
        'Oʻktam',
        'Anna-Mariya',
        'Иванов',
        'Ўктам',
        'Sh. '.replaceAll('.', ''),
        'Abdu Salom',
      ]) {
        expect(validateStudentName(ok), isNull, reason: ok);
      }
    });
    test('rejects empty / short / long / bad chars', () {
      expect(validateStudentName('   '), StudentNameError.required);
      expect(validateStudentName('A'), StudentNameError.length);
      expect(validateStudentName('A' * 61), StudentNameError.length);
      expect(validateStudentName('A' * 60), isNull);
      expect(validateStudentName('Ali1'), StudentNameError.chars);
      expect(validateStudentName('Ali_'), StudentNameError.chars);
      expect(validateStudentName('<b>'), StudentNameError.chars);
    });
    test('normalize trims and collapses whitespace', () {
      expect(normalizeStudentName('  Abdu   Salom \n'), 'Abdu Salom');
    });
  });

  group('AddStudentDraft', () {
    test('toJson: optional fields only when set, confirm_new only when true',
        () {
      final full = _draft().toJson();
      expect(full, {
        'first_name': 'Ali',
        'last_name': 'Valiyev',
        'birth_date': '2015-03-04',
        'parent_fio': 'Valiyev Karim',
        'client_temp_id': 'new:abc',
      });
      expect(_draft().toJson(confirmNew: true)['confirm_new'], true);
      final min = const AddStudentDraft(
              firstName: 'A1', lastName: 'B1', clientTempId: 'new:x')
          .toJson();
      expect(min.containsKey('birth_date'), isFalse);
      expect(min.containsKey('parent_fio'), isFalse);
      expect(min.containsKey('confirm_new'), isFalse);
    });
    test('newTempId is new:<uuid>, unique', () {
      final a = AddStudentDraft.newTempId();
      expect(a, startsWith('new:'));
      expect(isLocalNewStudentId(a), isTrue);
      expect(isLocalNewStudentId('123e4567'), isFalse);
      expect(AddStudentDraft.newTempId(), isNot(a));
    });
  });

  group('parseAddStudentResponse', () {
    test('monitoring 201 -> pending result usable as student_id', () {
      final r = parseAddStudentResponse(
          _json(201, {
            'id': 'u-1',
            'status': 'pending',
            'pending': true,
            'name': 'Valiyev Ali',
            'first_name': 'Ali',
            'last_name': 'Valiyev',
            'group_id': 'g1',
            'grade': 4,
            'language': 'uz',
          }),
          diagnostic: false);
      expect(r.id, 'u-1');
      expect(r.pending, isTrue);
      expect(r.queuedLocally, isFalse);
      expect(r.toRosterRow()['pending'], true);
      expect(r.toRosterRow()['id'], 'u-1');
    });
    test('diagnostic row shape', () {
      final r = parseAddStudentResponse(
          _json(200, {
            'attempt_id': 'att-9',
            'student_name': 'Valiyev Ali',
            'class_label': '4-A',
            'language': 'ru',
            'status': 'not_started',
            'pending': true,
            'add_request_id': 'r1',
          }),
          diagnostic: true);
      expect(r.toDiagnosticRow(), {
        'attempt_id': 'att-9',
        'student_name': 'Valiyev Ali',
        'class_label': '4-A',
        'language': 'ru',
        'status': 'not_started',
        'pending': true,
      });
    });
    test('409 similar_students -> SimilarStudentsException with candidates',
        () {
      expect(
          () => parseAddStudentResponse(
              _json(409, {
                'code': 'similar_students',
                'candidates': [
                  {
                    'id': 7,
                    'name': 'Valiyev Ali',
                    'grade': 4,
                    'group_name': '4-B'
                  },
                  {'name': 'no id is dropped'},
                ]
              }),
              diagnostic: false),
          throwsA(isA<SimilarStudentsException>()
              .having((e) => e.candidates.length, 'n', 1)
              .having((e) => e.candidates.first.id, 'id', '7')
              .having((e) => e.candidates.first.groupName, 'g', '4-B')));
    });
    test('other errors keep the machine code', () {
      expect(
          () => parseAddStudentResponse(_json(409, {'code': 'pending_limit'}),
              diagnostic: false),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'pending_limit')
              .having((e) => e is SimilarStudentsException, 'sim', false)));
      expect(
          () => parseAddStudentResponse(
              _json(400, {'code': 'invalid_name', 'detail': 'bad'}),
              diagnostic: false),
          throwsA(isA<ApiException>()
              .having((e) => e.code, 'code', 'invalid_name')
              .having((e) => e.message, 'msg', 'bad')));
    });
    test('2xx without an id is an error, not a phantom student', () {
      expect(() => parseAddStudentResponse(_json(200, {}), diagnostic: false),
          throwsA(isA<ApiException>()));
    });
  });

  group('local queue (add_student kind)', () {
    late Directory tmp;
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('add_student_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    });
    tearDown(() async {
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    test('shouldQueueAddStudent: network/old-backend yes, real answers no', () {
      for (final c in [0, 404, 405, 429, 502, 503, 504]) {
        expect(shouldQueueAddStudent(ApiException(c, 'x')), isTrue,
            reason: '$c');
      }
      for (final c in [400, 401, 403, 409, 500]) {
        expect(shouldQueueAddStudent(ApiException(c, 'x')), isFalse,
            reason: '$c');
      }
    });

    test('network failure -> queued locally, usable with the temp id',
        () async {
      final api = _FakeApi()..addError = const ApiException(0, "Internet yo'q");
      final r = await addStudentOrQueue(
          groupId: 'g1',
          draft: _draft(),
          confirmNew: false,
          grade: 4,
          language: 'uz',
          apiOverride: api);
      expect(r.queuedLocally, isTrue);
      expect(r.id, 'new:abc');
      expect(r.pending, isTrue);

      final queue = await OfflineQueue.peekLocalQueue();
      expect(queue, hasLength(1));
      expect(queue.single['_offlineKind'], 'add_student');
      expect(queue.single['client_temp_id'], 'new:abc');
      expect(queue.single['birth_date'], '2015-03-04');
      expect(queue.single['parent_fio'], 'Valiyev Karim');

      final local = await LocalStudentsDb.unsyncedForGroup('g1');
      expect(local.single.tempId, 'new:abc');
      expect(local.single.toRosterRow()['pending'], true);
      expect(await LocalStudentsDb.unsyncedForGroup('other'), isEmpty);

      // Idempotent: the same attempt queued twice stays one row.
      await addStudentOrQueue(
          groupId: 'g1', draft: _draft(), confirmNew: false, apiOverride: api);
      expect(await OfflineQueue.peekLocalQueue(), hasLength(1));
      expect(await LocalStudentsDb.unsyncedForGroup('g1'), hasLength(1));
    });

    test('old backend (404) is queued; 400 / 409 / similar are surfaced',
        () async {
      final api = _FakeApi()..addError = const ApiException(404, 'x');
      expect(
          (await addStudentOrQueue(
                  groupId: 'g',
                  draft: _draft(),
                  confirmNew: false,
                  apiOverride: api))
              .queuedLocally,
          isTrue);

      for (final e in <ApiException>[
        const ApiException(400, 'x', code: 'invalid_name'),
        const ApiException(409, 'x', code: 'pending_limit'),
        const SimilarStudentsException([SimilarStudent(id: '1', name: 'n')]),
      ]) {
        api.addError = e;
        await expectLater(
            addStudentOrQueue(
                groupId: 'g',
                draft: _draft('new:other'),
                confirmNew: false,
                apiOverride: api),
            throwsA(same(e)));
      }
      expect(await OfflineQueue.peekLocalQueue(), hasLength(1));
    });

    test('success is not queued', () async {
      final api = _FakeApi();
      final r = await addStudentOrQueue(
          groupId: 'g', draft: _draft(), confirmNew: false, apiOverride: api);
      expect(r.id, 'srv-1');
      expect(r.queuedLocally, isFalse);
      expect(await OfflineQueue.peekLocalQueue(), isEmpty);
    });

    test(
        'flush: add_student goes first with confirm_new, then the result made '
        'meanwhile is re-pointed from new:<uuid> to the server id', () async {
      final api = _FakeApi()..addError = const ApiException(0, 'offline');
      await addStudentOrQueue(
          groupId: 'g1', draft: _draft(), confirmNew: false, apiOverride: api);
      await OfflineQueue.enqueueLocal({
        'name': 'Valiyev Ali',
        'student_id': 'new:abc',
        'group_id': 'g1',
        'detail': {'test_key': 't'},
      }, 'result-token-1');
      // A normal roster student's result must be untouched.
      await OfflineQueue.enqueueLocal(
          {'name': 'Other', 'student_id': 'real-1'}, 'result-token-2');

      api.addError = null; // network is back
      api.addCalls.clear();
      final n = await api.flushOfflineQueue();
      expect(n, 3);

      expect(api.addCalls, [('g1', 'new:abc', true)]);
      expect(api.submitted.map((e) => e['student_id']), ['srv-1', 'real-1']);
      expect(await LocalStudentsDb.serverIdFor('new:abc'), 'srv-1');
      // Accepted -> the server roster returns it; no longer a local-only row.
      expect(await LocalStudentsDb.unsyncedForGroup('g1'), isEmpty);
      expect(await OfflineQueue.pendingLocalCount(), 0);
    });

    test('flush: add still failing keeps the row; result goes with temp id',
        () async {
      final api = _FakeApi()..addError = const ApiException(404, 'old backend');
      await addStudentOrQueue(
          groupId: 'g1', draft: _draft(), confirmNew: false, apiOverride: api);
      await OfflineQueue.enqueueLocal(
          {'name': 'Valiyev Ali', 'student_id': 'new:abc'}, 'result-token-1');

      final n = await api.flushOfflineQueue();
      expect(n, 1); // only the result
      expect(api.submitted.single['student_id'], 'new:abc');
      expect(await OfflineQueue.pendingLocalCount(), 1); // add retries later
      expect(await LocalStudentsDb.unsyncedForGroup('g1'), hasLength(1));
    });

    test('flush: a 400 drops the add and the local child', () async {
      final api = _FakeApi()
        ..addError = const ApiException(400, 'x', code: 'invalid_group');
      await queueAddStudentLocally(groupId: 'g1', draft: _draft());
      await api.flushOfflineQueue();
      expect(await OfflineQueue.pendingLocalCount(), 0);
      expect(await LocalStudentsDb.unsyncedForGroup('g1'), isEmpty);
    });

    test('purgeStale drops old local_students rows only', () async {
      await LocalStudentsDb.add(
          const LocalStudent(
              tempId: 'new:old', groupId: 'g', firstName: 'A1', lastName: 'B1'),
          nowMs: 1000);
      await LocalStudentsDb.add(const LocalStudent(
          tempId: 'new:fresh', groupId: 'g', firstName: 'A2', lastName: 'B2'));
      await OfflineQueue.purgeStale();
      expect((await LocalStudentsDb.unsyncedForGroup('g')).map((e) => e.tempId),
          ['new:fresh']);
    });
  });
}
