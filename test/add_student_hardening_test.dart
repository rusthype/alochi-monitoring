// "Bola qo'shish" client vs the hardened backend (T2 fixes S-001..S-012):
// string grades, other_class_matches, sticky rejection, new error codes,
// parent F.I.O. validation, held-result group binding and the
// max_attempts_exceeded classification of the result flush.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/local_students_db.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/models/add_student.dart';
import 'package:alochi_monitoring/core/offline/offline_new_student.dart';
import 'package:alochi_monitoring/core/services/add_student_service.dart';
import 'package:alochi_monitoring/features/test/engine_host_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:alochi_monitoring/shared/widgets/add_student_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

http.Response _json(int status, Object body) =>
    http.Response.bytes(utf8.encode(jsonEncode(body)), status,
        headers: {'content-type': 'application/json; charset=utf-8'});

Object _thrown(http.Response r, {required bool diagnostic}) {
  try {
    parseAddStudentResponse(r, diagnostic: diagnostic);
  } catch (e) {
    return e;
  }
  fail('expected an exception');
}

class _RejectApi extends MonitoringApi {
  Object error;
  _RejectApi(this.error);
  @override
  Future<AddStudentResult> addStudent({
    required String groupId,
    required AddStudentDraft draft,
    bool confirmNew = false,
  }) async =>
      throw error;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('string grades (backend sends "4")', () {
    test('SimilarStudent monitoring row {id,name,grade:"4",pending}', () {
      final c = SimilarStudent.fromJson(
          {'id': 'r1', 'name': 'Valiyev Ali', 'grade': '4', 'pending': true});
      expect(c.grade, 4);
      expect(c.pending, isTrue);
      expect(c.groupName, '');
    });
    test('SimilarStudent diagnostic row: attempt_id + class_label', () {
      final c = SimilarStudent.fromJson({
        'id': 'a1',
        'attempt_id': 'a1',
        'name': 'Valiyev Ali',
        'class_label': '4-A',
        'grade': '4-A',
      });
      expect(c.grade, 4);
      expect(c.groupName, '4-A');
      expect(c.attemptId, 'a1');
    });
    test('int, double, null, junk all parse without throwing', () {
      expect(parseIntLoose(4), 4);
      expect(parseIntLoose(4.0), 4);
      expect(parseIntLoose('5'), 5);
      expect(parseIntLoose(' 11-B '), 11);
      expect(parseIntLoose(null), 0);
      expect(parseIntLoose(''), 0);
      expect(parseIntLoose('abc'), 0);
      expect(
          SimilarStudent.fromJson({'id': 1, 'name': 'x', 'grade': 4}).grade, 4);
    });
    test('AddStudentResult.fromMonitoringJson accepts a String grade', () {
      final r = AddStudentResult.fromMonitoringJson({
        'id': 'u1',
        'status': 'pending',
        'pending': true,
        'first_name': 'Ali',
        'last_name': 'Valiyev',
        'group_id': 'g1',
        'grade': '4',
        'language': 'uz',
      });
      expect(r.grade, 4);
      expect(r.pending, isTrue);
    });
    test('201 with string grade goes through parseAddStudentResponse', () {
      final r = parseAddStudentResponse(
          _json(201, {'id': 'u1', 'status': 'pending', 'grade': '4'}),
          diagnostic: false);
      expect(r.grade, 4);
    });
    test('offline similarInRoster still builds int grades', () {
      final out = similarInRoster(
        roster: [
          {'id': 's1', 'name': 'Valiyev Ali', 'group_id': 'g1'}
        ],
        groups: [
          {'id': 'g1', 'name': '4-A', 'grade': '4'}
        ],
        firstName: 'Ali',
        lastName: 'Valiyev',
      );
      expect(out.single.groupName, '4-A');
    });
  });

  group('409 similar_students (class-scoped candidates + other classes)', () {
    final body = {
      'code': 'similar_students',
      'candidates': [
        {'id': 'r1', 'name': 'Valiyev Ali', 'grade': '4', 'pending': true},
        {'id': 's1', 'name': 'Valiyev Alisher', 'grade': '4'},
      ],
      'other_class_matches': [
        {'name': 'Valiyev Ali', 'class_label': '4-B'},
        {'class_label': 'no name is dropped'},
      ],
    };
    test('parsed incl. other_class_matches', () {
      final e = _thrown(_json(409, body), diagnostic: false)
          as SimilarStudentsException;
      expect(e.candidates.map((c) => c.id), ['r1', 's1']);
      expect(e.candidates.first.pending, isTrue);
      expect(e.otherClassMatches, hasLength(1));
      expect(e.otherClassMatches.single.name, 'Valiyev Ali');
      expect(e.otherClassMatches.single.classLabel, '4-B');
    });
    test('missing other_class_matches (old backend) -> empty', () {
      final e = _thrown(_json(409, {...body}..remove('other_class_matches')),
          diagnostic: false) as SimilarStudentsException;
      expect(e.otherClassMatches, isEmpty);
    });
    test('only other_class_matches, no candidates', () {
      final e = _thrown(
          _json(409, {
            'code': 'similar_students',
            'candidates': [],
            'other_class_matches': [
              {'name': 'Valiyev Ali', 'class_label': '4-B'}
            ],
          }),
          diagnostic: true) as SimilarStudentsException;
      expect(e.candidates, isEmpty);
      expect(e.otherClassMatches, hasLength(1));
    });
  });

  group('errors and rejection', () {
    test('pending_limit carries scope', () {
      final g = _thrown(_json(409, {'code': 'pending_limit', 'scope': 'group'}),
          diagnostic: false) as PendingLimitException;
      expect(g.isGroup, isTrue);
      expect(g.code, 'pending_limit');
      final s =
          _thrown(_json(409, {'code': 'pending_limit'}), diagnostic: false)
              as PendingLimitException;
      expect(s.isGroup, isFalse);
    });
    test('monitoring 200 status:rejected -> AddStudentRejectedException', () {
      final e = _thrown(
          _json(200, {'id': 'u1', 'status': 'rejected', 'pending': false}),
          diagnostic: false);
      expect(e, isA<AddStudentRejectedException>());
      expect((e as ApiException).code, kAddStudentRejectedCode);
    });
    test('diagnostic 200 pending:false -> rejected; pending:true is fine', () {
      expect(
          _thrown(
              _json(200, {
                'attempt_id': 'a1',
                'student_name': 'X Y',
                'status': 'not_started',
                'pending': false
              }),
              diagnostic: true),
          isA<AddStudentRejectedException>());
      final ok = parseAddStudentResponse(
          _json(201, {
            'attempt_id': 'a1',
            'student_name': 'X Y',
            'status': 'not_started',
            'pending': true
          }),
          diagnostic: true);
      expect(ok.id, 'a1');
    });
    Map<String, dynamic> diag(Map<String, dynamic> extra) => {
          'attempt_id': 'a1',
          'student_name': 'X Y',
          'add_request_id': 'r1',
          ...extra,
        };
    test('diagnostic request_status:rejected wins, even with pending:true', () {
      expect(
          _thrown(
              _json(
                  200,
                  diag({
                    'status': 'not_started',
                    'request_status': 'rejected',
                    'pending': true
                  })),
              diagnostic: true),
          isA<AddStudentRejectedException>());
    });
    test('diagnostic request_status:approved -> normal non-pending row', () {
      final r = parseAddStudentResponse(
          _json(
              200,
              diag({
                'status': 'partial',
                'request_status': 'approved',
                'pending': false
              })),
          diagnostic: true);
      expect(r.pending, isFalse);
      final row = r.toDiagnosticRow();
      expect(row['pending'], isFalse);
      expect(row['status'], 'partial');
    });
    test('diagnostic request_status:pending -> pending row; absent -> old rule',
        () {
      final p = parseAddStudentResponse(
          _json(
              201,
              diag({
                'status': 'not_started',
                'request_status': 'pending',
                'pending': true
              })),
          diagnostic: true);
      expect(p.pending, isTrue);
      expect(p.toDiagnosticRow()['status'], 'not_started');
      // Older backend (no request_status): pending:false => rejected.
      expect(
          _thrown(_json(200, diag({'status': 'not_started', 'pending': false})),
              diagnostic: true),
          isA<AddStudentRejectedException>());
    });
    test('an already-approved replay is NOT treated as rejected (monitoring)',
        () {
      final r = parseAddStudentResponse(
          _json(200, {'id': 'u1', 'status': 'approved', 'pending': false}),
          diagnostic: false);
      expect(r.pending, isFalse);
    });
    test(
        '400 invalid_parent_fio / invalid_name / invalid_client_temp_id keep code',
        () {
      for (final c in [
        'invalid_parent_fio',
        'invalid_name',
        'invalid_client_temp_id'
      ]) {
        final e =
            _thrown(_json(400, {'code': c}), diagnostic: false) as ApiException;
        expect(e.code, c);
        expect(e.statusCode, 400);
      }
    });
    test('429 is not queued interactively', () {
      expect(shouldQueueAddStudent(const ApiException(429, 'x')), isFalse);
      expect(shouldQueueAddStudent(const ApiException(404, 'x')), isTrue);
    });
  });

  group('parent F.I.O. + name validation mirror the backend', () {
    test('parent fio', () {
      for (final ok in [
        '',
        '   ',
        'Valiyev Karim',
        "Valiyev Karim O'g'li",
        'Иванов И.И.',
        'Valiyev, Karim - Aliyev',
        'A' * 120,
      ]) {
        expect(isValidParentFio(ok), isTrue, reason: ok);
      }
      for (final bad in [
        '1Karim',
        '-Karim',
        ' .Karim',
        'Karim 2',
        'Karim_',
        '<b>x</b>',
        'A' * 121,
        '.',
        ",",
      ]) {
        expect(isValidParentFio(bad), isFalse, reason: bad);
      }
    });
    test('names: no leading/trailing/doubled separators', () {
      expect(validateStudentName('Ali-'), StudentNameError.chars);
      expect(validateStudentName('-Ali'), StudentNameError.chars);
      expect(validateStudentName("Al''i"), StudentNameError.chars);
      expect(validateStudentName('Anna-Mariya'), isNull);
      expect(validateStudentName("G'ulom"), isNull);
    });
  });

  group('dialog', () {
    late AppLocalizations l10n;
    AddStudentOutcome? outcome;
    var closed = false;

    Future<void> open(WidgetTester tester, AddStudentSubmit onSubmit) async {
      outcome = null;
      closed = false;
      await tester.pumpWidget(MaterialApp(
        locale: const Locale('uz'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              onPressed: () async {
                outcome = await showAddStudentDialog(ctx, onSubmit: onSubmit);
                closed = true;
              },
              child: const Text('OPEN'),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      l10n =
          AppLocalizations.of(tester.element(find.byType(AddStudentDialog)))!;
    }

    Future<void> fill(WidgetTester tester) async {
      await tester.enterText(
          find.byKey(const Key('addStudentLastName')), 'Valiyev');
      await tester.enterText(
          find.byKey(const Key('addStudentFirstName')), 'Ali');
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('addStudentSubmit')));
      await tester.tap(find.byKey(const Key('addStudentSubmit')));
      await tester.pumpAndSettle();
    }

    testWidgets('other_class_matches only: step shows, "boshqa bola" resends',
        (tester) async {
      final confirms = <bool>[];
      await open(tester, (d, {required confirmNew}) async {
        confirms.add(confirmNew);
        if (!confirmNew) {
          throw const SimilarStudentsException([], otherClassMatches: [
            OtherClassMatch(name: 'Valiyev Ali', classLabel: '4-B')
          ]);
        }
        return const AddStudentResult(id: 'srv', name: 'Valiyev Ali');
      });
      await fill(tester);
      await submit(tester);

      expect(
          find.byKey(const Key('addStudentOtherClassWarning')), findsOneWidget);
      expect(find.text(l10n.addStudentOtherClassMatch('Valiyev Ali', '4-B')),
          findsOneWidget);
      expect(find.byKey(const Key('addStudentNotThem')), findsOneWidget);
      expect(find.byKey(const Key('addStudentBackToForm')), findsOneWidget);
      expect(find.text(l10n.addStudentSimilarBody), findsNothing);
      expect(closed, isFalse);

      await tester.tap(find.byKey(const Key('addStudentNotThem')));
      await tester.pumpAndSettle();
      expect(confirms, [false, true]);
      expect(outcome, isA<AddStudentCreated>());
    });

    testWidgets(
        'transfer button only for other-class matches; sends transfer_claim '
        'with confirm_new', (tester) async {
      final seen = <(bool, TransferClaim?)>[];
      await open(tester, (d, {required confirmNew}) async {
        seen.add((confirmNew, d.transferClaim));
        if (!confirmNew) {
          throw const SimilarStudentsException([
            SimilarStudent(id: 'r1', name: 'Valiyev Ali', grade: 4)
          ], otherClassMatches: [
            OtherClassMatch(name: 'Valiyev Ali', classLabel: '4-B')
          ]);
        }
        return const AddStudentResult(id: 'srv', name: 'Valiyev Ali');
      });
      await fill(tester);
      await submit(tester);

      // one button for the single other-class match, none for the candidate
      expect(find.byKey(const Key('addStudentTransferClaim_0')), findsOneWidget);
      expect(find.byKey(const Key('addStudentTransferClaim_1')), findsNothing);
      expect(find.text(l10n.addStudentTransferYes), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('addStudentTransferClaim_0')));
      await tester.tap(find.byKey(const Key('addStudentTransferClaim_0')));
      await tester.pumpAndSettle();
      expect(seen.length, 2);
      expect(seen[0], (false, null));
      expect(seen[1].$1, isTrue);
      expect(seen[1].$2?.name, 'Valiyev Ali');
      expect(seen[1].$2?.classLabel, '4-B');
      expect(outcome, isA<AddStudentCreated>());
    });

    testWidgets('no other-class match -> no transfer button; "boshqa bola" '
        'sends no claim', (tester) async {
      final seen = <TransferClaim?>[];
      await open(tester, (d, {required confirmNew}) async {
        seen.add(d.transferClaim);
        if (!confirmNew) {
          throw const SimilarStudentsException([
            SimilarStudent(id: 'r1', name: 'Valiyev Ali', grade: 4)
          ]);
        }
        return const AddStudentResult(id: 'srv', name: 'Valiyev Ali');
      });
      await fill(tester);
      await submit(tester);
      expect(find.text(l10n.addStudentTransferYes), findsNothing);
      await tester.tap(find.byKey(const Key('addStudentNotThem')));
      await tester.pumpAndSettle();
      expect(seen, [null, null]);
    });

    testWidgets('candidates + other classes render together', (tester) async {
      await open(tester, (d, {required confirmNew}) async {
        throw const SimilarStudentsException([
          SimilarStudent(id: 'r1', name: 'Valiyev Ali', grade: 4)
        ], otherClassMatches: [
          OtherClassMatch(name: 'Valiyev Ali', classLabel: '4-B')
        ]);
      });
      await fill(tester);
      await submit(tester);
      expect(find.text(l10n.addStudentSimilarBody), findsOneWidget);
      expect(find.text('Valiyev Ali'), findsOneWidget);
      expect(
          find.byKey(const Key('addStudentOtherClassWarning')), findsOneWidget);
    });

    testWidgets('empty candidates AND empty other matches auto-confirm',
        (tester) async {
      final confirms = <bool>[];
      await open(tester, (d, {required confirmNew}) async {
        confirms.add(confirmNew);
        if (!confirmNew) throw const SimilarStudentsException([]);
        return const AddStudentResult(id: 'srv', name: 'x');
      });
      await fill(tester);
      await submit(tester);
      expect(confirms, [false, true]);
      expect(outcome, isA<AddStudentCreated>());
    });

    testWidgets('rejected child: blocking message, dialog stays, no outcome',
        (tester) async {
      await open(tester, (d, {required confirmNew}) async {
        throw const AddStudentRejectedException();
      });
      await fill(tester);
      await submit(tester);
      expect(find.text(l10n.addStudentErrRejected), findsOneWidget);
      expect(closed, isFalse);
      expect(outcome, isNull);
    });

    testWidgets('429 -> friendly throttle text; retry keeps the temp id',
        (tester) async {
      final ids = <String>[];
      await open(tester, (d, {required confirmNew}) async {
        ids.add(d.clientTempId);
        if (ids.length == 1) throw const ApiException(429, 'Throttled');
        return const AddStudentResult(id: 'srv', name: 'x');
      });
      await fill(tester);
      await submit(tester);
      expect(find.text(l10n.addStudentErrThrottled), findsOneWidget);
      await submit(tester);
      expect(ids[1], ids[0]);
      expect(outcome, isA<AddStudentCreated>());
    });

    testWidgets('pending_limit scope school vs group', (tester) async {
      Object err = const PendingLimitException('group');
      await open(tester, (d, {required confirmNew}) async => throw err);
      await fill(tester);
      await submit(tester);
      expect(find.text(l10n.addStudentErrPendingLimitGroup), findsOneWidget);
      err = const PendingLimitException('school');
      await submit(tester);
      expect(find.text(l10n.addStudentErrPendingLimit), findsOneWidget);
      expect(find.text(l10n.addStudentErrPendingLimitGroup), findsNothing);
    });

    testWidgets('invalid_parent_fio / invalid_name -> inline field errors',
        (tester) async {
      Object err = const ApiException(400, 'x', code: 'invalid_parent_fio');
      await open(tester, (d, {required confirmNew}) async => throw err);
      await fill(tester);
      await submit(tester);
      expect(find.text(l10n.addStudentParentFioChars), findsOneWidget);
      expect(find.byKey(const Key('addStudentError')), findsNothing);
      // Editing the field clears the server error.
      await tester.enterText(
          find.byKey(const Key('addStudentParentFio')), 'Karim');
      await tester.pump();
      err = const ApiException(400, 'x', code: 'invalid_name');
      await submit(tester);
      expect(find.text(l10n.addStudentErrInvalidName), findsNWidgets(2));
    });

    testWidgets('invalid_class / duplicate_student -> friendly banner',
        (tester) async {
      Object err = const ApiException(400, 'Xato: 400', code: 'invalid_class');
      await open(tester, (d, {required confirmNew}) async => throw err);
      await fill(tester);
      await submit(tester);
      expect(find.text(l10n.addStudentErrInvalidClass), findsOneWidget);
      expect(find.textContaining('Xato:'), findsNothing);
      err = const ApiException(409, 'Xato: 409', code: 'duplicate_student');
      await submit(tester);
      expect(find.text(l10n.addStudentErrDuplicate), findsOneWidget);
      expect(find.textContaining('Xato:'), findsNothing);
      expect(closed, isFalse);
    });

    testWidgets('invalid_birth_date -> inline error on the date field',
        (tester) async {
      await open(tester, (d, {required confirmNew}) async {
        throw const ApiException(400, 'x', code: 'invalid_birth_date');
      });
      await fill(tester);
      await submit(tester);
      expect(find.text(l10n.addStudentErrInvalidBirthDate), findsOneWidget);
      expect(find.byKey(const Key('addStudentError')), findsNothing);
    });

    testWidgets('candidate subtitle: class_label only, else grade',
        (tester) async {
      await open(tester, (d, {required confirmNew}) async {
        throw const SimilarStudentsException([
          SimilarStudent(id: 'a', name: 'Ali A', grade: 4, groupName: '4-A'),
          SimilarStudent(id: 'b', name: 'Vali B', grade: 4),
        ]);
      });
      await fill(tester);
      await submit(tester);
      expect(find.text('4-A'), findsOneWidget);
      expect(find.text(l10n.gradeClass(4)), findsOneWidget);
      expect(find.textContaining(' · '), findsNothing);
    });

    testWidgets('invalid_client_temp_id -> generic banner', (tester) async {
      await open(tester, (d, {required confirmNew}) async {
        throw const ApiException(400, 'x', code: 'invalid_client_temp_id');
      });
      await fill(tester);
      await submit(tester);
      expect(find.text(l10n.addStudentErrGeneric), findsOneWidget);
    });

    testWidgets('client-side parent F.I.O. validation blocks submit',
        (tester) async {
      var calls = 0;
      await open(tester, (d, {required confirmNew}) async {
        calls++;
        return const AddStudentResult(id: 'srv', name: 'x');
      });
      await fill(tester);
      await tester.enterText(
          find.byKey(const Key('addStudentParentFio')), '1Karim');
      await submit(tester);
      expect(find.text(l10n.addStudentParentFioChars), findsOneWidget);
      expect(calls, 0);
      await tester.enterText(
          find.byKey(const Key('addStudentParentFio')), 'Karim');
      await submit(tester);
      expect(calls, 1);
      expect(closed, isTrue);
    });
  });

  group('queue + held-result flush', () {
    late Directory tmp;
    setUpAll(() {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    });
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('add_student_hard_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    });
    tearDown(() async {
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    AddStudentDraft draft() => const AddStudentDraft(
        firstName: 'Ali', lastName: 'Valiyev', clientTempId: 'new:abc');

    test('queued add: 429 keeps retrying, rejected child is dropped', () async {
      await queueAddStudentLocally(groupId: 'g1', draft: draft());
      final throttled = _RejectApi(const ApiException(429, 'x'));
      await OfflineQueue.flushLocal(
          (payload, token) => throttled.submitQueuedAddStudent(payload));
      expect(await OfflineQueue.pendingLocalCount(), 1);
      expect(await LocalStudentsDb.unsyncedForGroup('g1'), hasLength(1));

      final rejected = _RejectApi(const AddStudentRejectedException());
      await OfflineQueue.flushLocal(
          (payload, token) => rejected.submitQueuedAddStudent(payload));
      expect(await OfflineQueue.pendingLocalCount(), 0);
      expect(await LocalStudentsDb.unsyncedForGroup('g1'), isEmpty);
    });

    test('pending child: payload group_id == the group it was added to',
        () async {
      // Child added (queued) while group gA was selected.
      await queueAddStudentLocally(
          groupId: 'gA', draft: draft(), grade: 4, language: 'uz');
      final row =
          (await LocalStudentsDb.unsyncedForGroup('gA')).single.toRosterRow();
      expect(await LocalStudentsDb.unsyncedForGroup('gB'), isEmpty);

      // StudentEntryScreen launches the runner with the SELECTED group id and
      // the roster row id -> EngineHostScreen builds this identity block.
      final payload = resultIdentityFields(
          group: '4-A', groupId: 'gA', studentId: row['id'].toString());
      expect(payload['group_id'], 'gA');
      expect(payload['student_id'], 'new:abc');
      expect(payload['group_name'], '4-A');

      // Pack mode: the new_student block's group_id equals the payload's.
      final withBlock = attachNewStudent({
        ...payload,
        'name': 'Valiyev Ali'
      }, [
        {...row, 'group_id': 'gA'}
      ]);
      expect(
          (withBlock['new_student'] as Map)['group_id'], withBlock['group_id']);

      // Online child (server id): same rule.
      final online = resultIdentityFields(
          group: '4-A', groupId: 'gA', studentId: 'req-uuid');
      expect(online['group_id'], 'gA');
      // No group -> empty string (backend then does not hold it).
      expect(resultIdentityFields(studentId: 's')['group_id'], '');
    });

    test('409 max_attempts_exceeded on a held child is PERMANENT (no retry)',
        () async {
      final client = MockClient((req) async => _json(409, {
            'error': 'max_attempts_exceeded',
            'detail': 'Bu test uchun urinishlar soni tugagan.',
            'attempts_used': 1,
            'max_attempts': 1,
          }));
      final a = MonitoringApi();
      final out = await http.runWithClient(
          () => a.submitLocalResultFull({
                'student_id': 'req-uuid',
                'group_id': 'gA',
              }, 'tok-1'),
          () => client);
      expect(out['synced'], isFalse);
      expect(out['permanent'], isTrue);

      // ...and the queue drops the row instead of retrying forever.
      await OfflineQueue.enqueueLocal(
          {'student_id': 'req-uuid', 'group_id': 'gA'}, 'tok-1');
      final n = await http.runWithClient(
          () => OfflineQueue.flushLocal((payload, token) async =>
              await a.submitLocalResultFull(payload, token)),
          () => client);
      expect(n, 0);
      expect(await OfflineQueue.pendingLocalCount(), 0);
    });

    test('429 / 5xx on a held child stay retryable', () async {
      final a = MonitoringApi();
      for (final code in [429, 500, 503]) {
        final out = await http.runWithClient(
            () => a.submitLocalResultFull({'student_id': 'x'}, 't'),
            () => MockClient((_) async => _json(code, {})));
        expect(out['permanent'], isFalse, reason: '$code');
      }
    });
  });
}
