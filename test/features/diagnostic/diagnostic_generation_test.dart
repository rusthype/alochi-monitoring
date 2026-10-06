// Stale-state protection after an admin reset/retake: saved_answers seeding,
// per-row generation, `generation` in sync/finish bodies, and the
// stale_generation (409) handling that is distinct from a plain 409.
import 'dart:convert';

import 'package:alochi_monitoring/core/api/api_client.dart' show ApiException;
import 'package:alochi_monitoring/core/db/diagnostic_answer_store.dart';
import 'package:alochi_monitoring/core/sync/sync_service.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_kiosk_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _ids = ['q1', 'q2', 'q3'];

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async => DiagnosticAnswerStore.openInMemory());
  tearDown(() async => DiagnosticAnswerStore.reset());

  group('DiagnosticAnswerStore.seedSynced', () {
    test('seeds missing rows as synced, index from question order', () async {
      await DiagnosticAnswerStore.seedSynced(
        attemptId: 'a1',
        subject: 'math',
        saved: {'q3': 'D', 'q1': 'A'},
        orderedQuestionIds: _ids,
        generation: 1,
      );
      final rows = await DiagnosticAnswerStore.loadAll('a1', subject: 'math');
      expect(rows.map((r) => r['question_id']), ['q1', 'q3']);
      expect(rows.map((r) => r['question_index']), [1, 3]);
      expect(
          rows.every((r) => r['synced'] == 1 && r['generation'] == 1), isTrue);
      // Seeded rows are never re-uploaded.
      expect(await DiagnosticAnswerStore.pendingForAttempt('a1'), isEmpty);
    });

    test('local row wins over the server value and stays unsynced', () async {
      await DiagnosticAnswerStore.saveAnswer(
        attemptId: 'a1',
        subject: 'math',
        questionIndex: 2,
        questionId: 'q2',
        selectedOption: 'C',
        generation: 1,
      );
      await DiagnosticAnswerStore.seedSynced(
        attemptId: 'a1',
        subject: 'math',
        saved: {'q2': 'B'},
        orderedQuestionIds: _ids,
        generation: 1,
      );
      final rows = await DiagnosticAnswerStore.loadAll('a1', subject: 'math');
      expect(rows, hasLength(1));
      expect(rows.single['selected_option'], 'C');
      expect(rows.single['synced'], 0);
    });

    test('ignores question ids that are not in the question list', () async {
      await DiagnosticAnswerStore.seedSynced(
        attemptId: 'a1',
        subject: 'math',
        saved: {'zzz': 'A'},
        orderedQuestionIds: _ids,
      );
      expect(
          await DiagnosticAnswerStore.loadAll('a1', subject: 'math'), isEmpty);
    });
  });

  group('DiagnosticAnswerStore generation', () {
    test('saveAnswer stores generation; clearGeneration drops only that one',
        () async {
      for (final g in [1, 2]) {
        await DiagnosticAnswerStore.saveAnswer(
          attemptId: 'a1',
          subject: 'math',
          questionIndex: g,
          questionId: 'q$g',
          selectedOption: 'A',
          generation: g,
        );
      }
      await DiagnosticAnswerStore.clearGeneration('a1', 1);
      final rows = await DiagnosticAnswerStore.loadAll('a1', subject: 'math');
      expect(rows.map((r) => r['question_id']), ['q2']);
    });

    test('v1 -> v2 upgrade adds the nullable generation column', () async {
      final db = await openDatabase(inMemoryDatabasePath,
          version: 1,
          singleInstance: false,
          onCreate: (db, _) => db.execute(
              'CREATE TABLE local_diagnostic_answers (id INTEGER PRIMARY KEY, '
              'attempt_id TEXT, synced INTEGER)'));
      await DiagnosticAnswerStore.upgrade(db, 1, 2);
      await db.insert('local_diagnostic_answers',
          {'attempt_id': 'a', 'synced': 0, 'generation': 4});
      final rows = await db.query('local_diagnostic_answers');
      expect(rows.single['generation'], 4);
      await db.close();
    });
  });

  group('kiosk API generation', () {
    test('syncAnswers / finishAttempt send generation only when known',
        () async {
      final bodies = <String, Map<String, dynamic>>{};
      await http.runWithClient(() async {
        await diagnosticKioskApi.syncAnswers(
            attemptId: 'a1', answers: const [], generation: 3);
        await diagnosticKioskApi.finishAttempt(
            attemptId: 'a1', answers: const [], generation: 3);
        await diagnosticKioskApi
            .finishAttempt(attemptId: 'a2', answers: const []);
      },
          () => MockClient((req) async {
                final b = jsonDecode(req.body) as Map<String, dynamic>;
                bodies['${req.url.path}|${b['attempt_id']}'] = b;
                return http.Response('{}', 200);
              }));
      expect(bodies['/api/v1/diagnostic/kiosk/sync/|a1']!['generation'], 3);
      expect(bodies['/api/v1/diagnostic/kiosk/finish/|a1']!['generation'], 3);
      expect(bodies['/api/v1/diagnostic/kiosk/finish/|a2'],
          isNot(contains('generation')));
    });

    test('409 body code is exposed on ApiException', () async {
      await http.runWithClient(() async {
        try {
          await diagnosticKioskApi.syncAnswers(
              attemptId: 'a1', answers: const [], generation: 1);
          fail('expected ApiException');
        } on ApiException catch (e) {
          expect(e.statusCode, 409);
          expect(e.code, 'stale_generation');
        }
      },
          () => MockClient((_) async => http.Response(
              jsonEncode({'detail': 'x', 'code': 'stale_generation'}), 409)));
    });

    test('queued finish with stale_generation is dropped (permanent)', () {
      final r = classifyFinishOfflineResponse(
          409, jsonEncode({'detail': 'x', 'code': 'stale_generation'}));
      expect(r, {'synced': false, 'permanent': true});
      // plain 409 (no code, other detail) stays retryable as before
      final plain = classifyFinishOfflineResponse(
          409, jsonEncode({'detail': 'boshqa xato'}));
      expect(plain['permanent'], false);
    });
  });

  group('SyncService.flushDiagnosticAnswers', () {
    Future<void> seedPending(int gen, String qid, int idx) =>
        DiagnosticAnswerStore.saveAnswer(
          attemptId: 'a1',
          subject: 'math',
          questionIndex: idx,
          questionId: qid,
          selectedOption: 'A',
          generation: gen,
        );

    Future<void> flush(http.Response Function(http.Request) respond) =>
        http.runWithClient(
            () => SyncService.instance.flushDiagnosticAnswers('a1'),
            () => MockClient((req) async => respond(req)));

    test('sends each row group with its generation and marks synced', () async {
      await seedPending(2, 'q1', 1);
      final sent = <int?>[];
      await flush((req) {
        sent.add((jsonDecode(req.body) as Map)['generation'] as int?);
        return http.Response('{}', 200);
      });
      expect(sent, [2]);
      expect(await DiagnosticAnswerStore.pendingForAttempt('a1'), isEmpty);
    });

    test('stale_generation drops the stale rows, keeps newer ones', () async {
      await seedPending(1, 'q1', 1); // stale
      await seedPending(2, 'q2', 2); // current
      await flush((req) {
        final g = (jsonDecode(req.body) as Map)['generation'];
        return g == 1
            ? http.Response(
                jsonEncode({'detail': 'x', 'code': 'stale_generation'}), 409)
            : http.Response('{}', 200);
      });
      final rows = await DiagnosticAnswerStore.loadAll('a1', subject: 'math');
      expect(rows.map((r) => r['question_id']), ['q2']); // q1 cleared
      expect(rows.single['synced'], 1); // q2 uploaded
    });

    test('plain 409 (already finished) still marks rows synced, not cleared',
        () async {
      await seedPending(1, 'q1', 1);
      await flush((_) => http.Response(
          jsonEncode({'detail': 'Attempt allaqachon yakunlangan'}), 409));
      final rows = await DiagnosticAnswerStore.loadAll('a1', subject: 'math');
      expect(rows.single['synced'], 1);
    });
  });
}
