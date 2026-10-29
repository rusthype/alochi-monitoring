// Crash-recovery double-submit protection (attempt_id nonce).
//
// The completion idempotency token is derived from a one-time `attempt_id`
// minted when the attempt record is created and never rewritten, and the
// record is marked `completed` (with its final answers) before onComplete.
// A crash between enqueue and AttemptStore.clear therefore replays the SAME
// snapshot with the SAME token, while a retake gets a different token.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:alochi_monitoring/core/api/api_client.dart'
    show newIdempotencyToken;
import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/features/test/engine_host_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';

const _testKey = 'attempt_id_test_v1';
const _student = 'S-77';

Map<String, dynamic> _specJson() => {
      'test_key': _testKey,
      'title': 'Attempt Id Test',
      'grade': 5,
      'version': 1,
      'parts': ['Math'],
      'variants': {
        '1': {
          'Math': [
            {
              'type': 'text_choice',
              'q': 'Q1',
              'opts': ['Alpha', 'Beta'],
              'ans': 0,
            },
          ],
        },
      },
    };

Map<String, dynamic> _record({
  String? attemptId,
  bool completed = false,
  Map<String, dynamic>? answers,
  String student = _student,
}) =>
    {
      'variant': 1,
      'answers': answers ?? <String, dynamic>{},
      'started_at': DateTime.now().millisecondsSinceEpoch,
      if (attemptId != null) 'attempt_id': attemptId,
      if (completed) 'completed': true,
      // Still in the future: this is the "resumed, not expired" case.
      'deadline_epoch_ms':
          DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      'student_name': 'Ism Familiya',
      'student_id': student,
      'group_name': '',
    };

Future<int> _queueRows() async {
  final d = await OfflineQueue.db;
  return (await d.query('local_queue')).length;
}

Widget _engine({
  required void Function(dynamic result, int? secs) onComplete,
  VoidCallback? onExpired,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TestEngine(
        spec: TestSpec.fromJson(_specJson()),
        variant: 1,
        firstName: 'Ism',
        lastName: 'Familiya',
        school: '56',
        studentId: _student,
        duration: const Duration(minutes: 10),
        onComplete: onComplete,
        onExpiredAutoSubmit: onExpired,
      ),
    );

Future<void> _letRestoreRun(WidgetTester tester) async {
  // Restore/persist talk to SharedPreferences + QueueCrypto on the real loop.
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    // See engine_finish_confirm_test.dart: resolve QueueCrypto's cached key
    // on the real event loop, not inside a testWidgets FakeAsync zone.
    await QueueCrypto.encryptPayload('{}');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('attempt_id_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
  });

  tearDown(() async {
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  test(
      'crash after enqueue but before clear: replay derives the SAME token '
      'and leaves exactly ONE queue row', () async {
    await AttemptStore.save(
        _testKey, _record(attemptId: 'nonce-1', completed: true));

    final first = await resolveResultToken(_testKey, _student);
    await OfflineQueue.enqueueLocal({'total_pct': 100}, first);
    // -- crash: AttemptStore.clear never ran, record survives --

    final replay = await resolveResultToken(_testKey, _student);
    await OfflineQueue.enqueueLocal({'total_pct': 100}, replay);

    expect(replay, first);
    expect(first, buildResultToken(_testKey, _student, 'nonce-1'));
    expect(await _queueRows(), 1);
  });

  test('after a normal completion + clear, a NEW attempt gets a new token',
      () async {
    await AttemptStore.save(
        _testKey, _record(attemptId: newIdempotencyToken(), completed: true));
    final a = await resolveResultToken(_testKey, _student);
    await OfflineQueue.enqueueLocal({'n': 1}, a);
    await AttemptStore.clear(_testKey);

    // runner_dispatch seeds a fresh record (fresh nonce) for the retake.
    await AttemptStore.save(
        _testKey, _record(attemptId: newIdempotencyToken()));
    final b = await resolveResultToken(_testKey, _student);
    await OfflineQueue.enqueueLocal({'n': 2}, b);

    expect(b, isNot(a));
    expect(await _queueRows(), 2);
  });

  test(
      'old-format record (no attempt_id) uses the SAME token as the recovery '
      'scan; a record with no identity, a missing record or another '
      "student's record fall back to a random token without crashing",
      () async {
    // Contract change (audit wave 3): a legacy record used to get a random
    // token here while the startup scan derived `rec-<started_at>` - a crash
    // between enqueue and clear then submitted twice.
    final legacy = _record();
    await AttemptStore.save(_testKey, legacy);
    final old1 = await resolveResultToken(_testKey, _student);
    final old2 = await resolveResultToken(_testKey, _student);
    expect(old1, old2);
    expect(old1, tokenForStoredAttempt(_testKey, legacy));

    await AttemptStore.save(_testKey, _record()..remove('started_at'));
    final anon1 = await resolveResultToken(_testKey, _student);
    final anon2 = await resolveResultToken(_testKey, _student);
    expect(anon1.startsWith('mw-'), isFalse);
    expect(anon1, isNot(anon2));

    await AttemptStore.clear(_testKey);
    expect((await resolveResultToken(_testKey, _student)).isNotEmpty, isTrue);

    await AttemptStore.save(_testKey, _record(attemptId: 'x', student: 'S-1'));
    expect((await resolveResultToken(_testKey, _student)).startsWith('mw-'),
        isFalse);
  });

  testWidgets(
      'resumed COMPLETED record replays its stored answers and never reopens '
      'for editing', (tester) async {
    // Stored answer is the correct one (index 0). The test must be scored
    // from this snapshot with no student input and no expired-notice.
    await tester.runAsync(() => AttemptStore.save(
        _testKey,
        _record(
            attemptId: 'nonce-9', completed: true, answers: {'Math/0': 0})));

    var completions = 0;
    var correct = -1;
    var expired = 0;
    await tester.pumpWidget(_engine(
      onComplete: (r, _) {
        completions++;
        correct = (r as dynamic).sectionScores.first.correct as int;
      },
      onExpired: () => expired++,
    ));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _letRestoreRun(tester);
    await _letRestoreRun(tester); // persist-then-onComplete hop

    expect(completions, 1);
    expect(correct, 1);
    expect(expired, 0);

    final saved = await tester.runAsync(() => AttemptStore.load(_testKey));
    expect(saved!['completed'], isTrue);
    expect(saved['attempt_id'], 'nonce-9');
    expect((saved['answers'] as Map)['Math/0'], 0);
  });

  testWidgets(
      'fresh run: record gets an attempt_id and is marked completed before '
      'onComplete, so the host token is the stable mw- token', (tester) async {
    var completions = 0;
    await tester.pumpWidget(_engine(onComplete: (_, __) => completions++));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _letRestoreRun(tester);

    await tester.tap(find.text('Alpha'));
    await tester.pump(const Duration(milliseconds: 100));
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    await tester.tap(find.widgetWithText(ElevatedButton, l10n.finish));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(ElevatedButton, l10n.finish),
    ));
    await tester.pump(const Duration(milliseconds: 300));
    await _letRestoreRun(tester);

    expect(completions, 1);
    final saved = await tester.runAsync(() => AttemptStore.load(_testKey));
    expect(saved!['completed'], isTrue);
    final id = saved['attempt_id'] as String;
    expect(id, isNotEmpty);
    final token =
        await tester.runAsync(() => resolveResultToken(_testKey, _student));
    expect(token, buildResultToken(_testKey, _student, id));
  });
}
