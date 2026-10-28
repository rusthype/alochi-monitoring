// Audit regression tests for the TestEngine flow:
//  E-03  restored yes_no answer must not be overwritten by a stale controller
//  E-11  double-click Finish stacks one dialog; remote end closes it
//  E-12  a failing onComplete never leaves a dead Finish button
//  E-10  restore: skeleton gate, corrupt record falls back to a fresh attempt
//  E-08  a saved attempt of another test version is discarded
//  E-13  lifecycle change flushes the attempt immediately
//  E-18/E-25 extra time while paused, negative delta is silent
//  E-22  A -> B -> A section switching throws no GlobalKey error

import 'dart:async';

import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/engine/test_scorer.dart';
import 'package:alochi_monitoring/core/services/heartbeat_service.dart';
import 'package:alochi_monitoring/core/widgets/skeleton.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _testKey = 'audit_flow_v1';
const _student = 'S-AUDIT';

Map<String, dynamic> _specJson({int version = 1}) => {
      'test_key': _testKey,
      'title': 'Audit Flow',
      'grade': 5,
      'version': version,
      'parts': ['SecA', 'SecB'],
      'variants': {
        '1': {
          'SecA': [
            {'type': 'yes_no', 'q': 'YN-QUESTION', 'ans': 'YES'},
            {
              'type': 'text_choice',
              'q': 'TC-QUESTION',
              'opts': ['Alpha', 'Beta'],
              'ans': 0,
            },
          ],
          'SecB': [
            {
              'type': 'spelling',
              'scramble': 'tac',
              'ans': 'cat',
            },
          ],
        },
      },
    };

Map<String, dynamic> _record({
  Map<String, dynamic>? answers,
  Object? answersRaw,
  Object? testVersion,
  bool completed = false,
}) =>
    {
      'variant': 1,
      'answers': answersRaw ?? answers ?? <String, dynamic>{},
      if (testVersion != null) 'test_version': testVersion,
      'started_at': DateTime.now().millisecondsSinceEpoch,
      'attempt_id': 'nonce-audit',
      if (completed) 'completed': true,
      'deadline_epoch_ms':
          DateTime.now().add(const Duration(minutes: 5)).millisecondsSinceEpoch,
      'student_name': 'Ism Familiya',
      'student_id': _student,
      'group_name': '',
    };

Widget _engine({
  required FutureOr<void> Function(ScoredResult r, int? secs) onComplete,
  int version = 1,
}) =>
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TestEngine(
        spec: TestSpec.fromJson(_specJson(version: version)),
        variant: 1,
        firstName: 'Ism',
        lastName: 'Familiya',
        school: '56',
        studentId: _student,
        duration: const Duration(minutes: 10),
        onComplete: (r, s) => onComplete(r, s),
      ),
    );

/// Gives real-IO futures (SharedPreferences / QueueCrypto) time to resolve.
Future<void> _io(WidgetTester tester, {int ms = 200}) async {
  await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
  await tester.pump(const Duration(milliseconds: 100));
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;

Future<void> _tapFinishAndConfirm(WidgetTester tester) async {
  final l10n = _l10n(tester);
  await tester.tap(find.widgetWithText(ElevatedButton, l10n.finish));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.tap(find.descendant(
    of: find.byType(AlertDialog),
    matching: find.widgetWithText(ElevatedButton, l10n.finish),
  ));
  await tester.pump(const Duration(milliseconds: 300));
  await _io(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Resolve QueueCrypto's cached key on the real event loop (see
    // engine_finish_confirm_test.dart).
    await QueueCrypto.encryptPayload('{}');
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets(
      'E-03: restored yes_no answer is not overwritten by stale controller '
      'text when the student changes it and switches section', (tester) async {
    await tester.runAsync(() => AttemptStore.save(
        _testKey,
        _record(answers: {
          'SecA/0': 'YES', // yes_no - used to get a controller holding "YES"
          'SecB/0': 'cat',
        })));
    ScoredResult? result;
    await tester.pumpWidget(_engine(onComplete: (r, _) => result = r));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);

    final l10n = _l10n(tester);
    await tester.tap(find.text(l10n.noOption));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text(l10n.nextButton)); // _syncTextAnswers runs
    await tester.pump(const Duration(milliseconds: 400));
    await _tapFinishAndConfirm(tester);

    expect(result, isNotNull);
    expect(result!.rawAnswers['SecA/0'], 'NO');
    expect(result!.rawAnswers['SecB/0'], 'cat');
  });

  testWidgets(
      'E-11: double-click Finish opens ONE dialog; a remote end '
      'closes it', (tester) async {
    ScoredResult? result;
    await tester.pumpWidget(_engine(onComplete: (r, _) => result = r));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);
    await tester.tap(find.text(_l10n(tester).nextButton));
    await tester.pump(const Duration(milliseconds: 400));

    final finish = find.widgetWithText(ElevatedButton, _l10n(tester).finish);
    await tester.tap(finish);
    await tester.tap(finish, warnIfMissed: false); // second click, same frame
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AlertDialog), findsOneWidget);

    // Admin ends the session while the dialog is open: it must go away.
    HeartbeatService.instance.reconcileProctorState(terminated: true);
    await tester.pump(const Duration(milliseconds: 300));
    await _io(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(result, isNotNull);
  });

  testWidgets('E-12: onComplete failing (sync or async) re-opens the test',
      (tester) async {
    var calls = 0;
    await tester.pumpWidget(_engine(onComplete: (r, _) async {
      calls++;
      if (calls == 1) throw StateError('boom async');
      if (calls == 2) throw StateError('boom again');
    }));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);
    await tester.tap(find.text(_l10n(tester).nextButton));
    await tester.pump(const Duration(milliseconds: 400));

    await _tapFinishAndConfirm(tester);
    expect(calls, 1);
    // Still on the test with a working Finish button.
    expect(find.byType(AlertDialog), findsNothing);
    await _tapFinishAndConfirm(tester);
    expect(calls, 2);
    await _tapFinishAndConfirm(tester);
    expect(calls, 3); // third time succeeds
    expect(tester.takeException(), isNull);
  });

  testWidgets('E-10: skeleton until the saved attempt is loaded',
      (tester) async {
    await tester.runAsync(
        () => AttemptStore.save(_testKey, _record(answers: {'SecA/1': 0})));
    await tester.pumpWidget(_engine(onComplete: (_, __) {}));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    // Restore needs real IO: nothing answerable is on screen yet.
    expect(find.byType(Skeleton), findsWidgets);
    expect(find.text('YN-QUESTION'), findsNothing);
    await _io(tester);
    expect(find.byType(Skeleton), findsNothing);
    expect(find.text('YN-QUESTION'), findsOneWidget);
  });

  testWidgets(
      'E-10: a corrupt saved record falls back to a fresh attempt '
      '(deadline set, timer started)', (tester) async {
    // `answers` of the wrong type used to throw out of the un-awaited
    // restore, leaving _deadlineMs null forever.
    await tester.runAsync(
        () => AttemptStore.save(_testKey, _record(answersRaw: 'not-a-map')));
    await tester.pumpWidget(_engine(onComplete: (_, __) {}));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);

    expect(find.text('YN-QUESTION'), findsOneWidget);
    final saved = await tester.runAsync(() => AttemptStore.load(_testKey));
    expect(saved!['deadline_epoch_ms'], isA<num>());
    expect(saved['answers'], isA<Map>());
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'E-08: an in-progress attempt of another test version is '
      'discarded; the current version is stored', (tester) async {
    await tester.runAsync(() => AttemptStore.save(
        _testKey, _record(answers: {'SecA/1': 1}, testVersion: 9)));
    await tester.pumpWidget(_engine(onComplete: (_, __) {}, version: 2));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);

    final saved = await tester.runAsync(() => AttemptStore.load(_testKey));
    expect((saved!['answers'] as Map), isEmpty);
    expect(saved['test_version'], 2);
  });

  testWidgets('E-08: same version resumes its answers', (tester) async {
    await tester.runAsync(() => AttemptStore.save(
        _testKey, _record(answers: {'SecA/1': 1}, testVersion: 2)));
    await tester.pumpWidget(_engine(onComplete: (_, __) {}, version: 2));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);
    // 1 of 3 answered
    expect(find.text('1/3'), findsOneWidget);
  });

  testWidgets(
      'E-13: a lifecycle change flushes the attempt without waiting '
      'for the debounce', (tester) async {
    await tester.pumpWidget(_engine(onComplete: (_, __) {}));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);

    await tester.tap(find.text('Alpha'));
    await tester.pump(); // no pump past the debounce window
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await _io(tester, ms: 150);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

    final saved = await tester.runAsync(() => AttemptStore.load(_testKey));
    expect((saved!['answers'] as Map)['SecA/1'], 0);
  });

  testWidgets(
      'E-18/E-25: extra time while paused is kept; a negative '
      'correction shows no toast', (tester) async {
    final hb = HeartbeatService.instance;
    await tester.pumpWidget(_engine(onComplete: (_, __) {}));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);

    try {
      hb.reconcileProctorState(locked: true);
      await _io(tester);
      final before =
          (await tester.runAsync(() => AttemptStore.load(_testKey)))!;
      final pausedBefore = before['paused_remaining_ms'] as num;

      hb.reconcileProctorState(extraTimeSeconds: 120);
      await _io(tester);
      final after = (await tester.runAsync(() => AttemptStore.load(_testKey)))!;
      expect((after['paused_remaining_ms'] as num) - pausedBefore, 120000);
      expect(find.text(_l10n(tester).timeAdded(2)), findsOneWidget);

      // Server lowers the cumulative total: delta -60 -> no "+1" toast.
      hb.reconcileProctorState(extraTimeSeconds: 60);
      await _io(tester);
      expect(find.text(_l10n(tester).timeAdded(1)), findsNothing);
      final neg = (await tester.runAsync(() => AttemptStore.load(_testKey)))!;
      expect((neg['paused_remaining_ms'] as num) - pausedBefore, 60000);
    } finally {
      hb.reconcileProctorState(locked: false);
    }
  });

  testWidgets('E-22: rapid A -> B -> A -> B section switching throws nothing',
      (tester) async {
    await tester.pumpWidget(_engine(onComplete: (_, __) {}));
    addTearDown(() => tester.pumpWidget(const SizedBox()));
    await _io(tester);

    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('SecB'));
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.text('SecA'));
      await tester.pump(const Duration(milliseconds: 60));
    }
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.takeException(), isNull);
    expect(find.text('YN-QUESTION'), findsOneWidget);
  });
}
