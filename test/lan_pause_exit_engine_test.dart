// Paused LAN test must survive: the kiosk inactivity logout must not pull a
// student out of a running (paused) test, leaving the engine must neither
// wipe the attempt nor leave the hub with a ghost session, and re-entering
// must come back paused with the time that was left (never a fresh timer).
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart'
    show newIdempotencyToken;
import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/core/services/heartbeat_service.dart';
import 'package:alochi_monitoring/core/widgets/inactivity_wrapper.dart';
import 'package:alochi_monitoring/features/session/runner_dispatch.dart'
    show resolveAttemptVariant;
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _testKey = 'lan_pause_exit_v1';
const _student = '00000000-0000-4000-8000-0000000000d1';

Map<String, dynamic> _specJson() => {
      'test_key': _testKey,
      'title': 'Pause test',
      'grade': 4,
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
  required int deadlineMs,
  int? pausedRemainingMs,
  String attemptId = 'attempt-1',
}) =>
    {
      'variant': 1,
      'answers': <String, dynamic>{'Math/0': 1},
      'started_at': DateTime.now().millisecondsSinceEpoch,
      'attempt_id': attemptId,
      'deadline_epoch_ms': deadlineMs,
      if (pausedRemainingMs != null) 'paused_remaining_ms': pausedRemainingMs,
      'student_name': 'Ism Familiya',
      'student_id': _student,
      'group_name': '',
    };

Widget _engine({VoidCallback? onExpired, void Function()? onComplete}) =>
    TestEngine(
      spec: TestSpec.fromJson(_specJson()),
      variant: 1,
      firstName: 'Ism',
      lastName: 'Familiya',
      school: '56',
      studentId: _student,
      duration: const Duration(minutes: 10),
      onComplete: (_, __) => onComplete?.call(),
      onExpiredAutoSubmit: onExpired,
    );

Widget _app(Widget home) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Future<void> _settle(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
  await tester.pump(const Duration(milliseconds: 100));
}

final _shield = find.byIcon(Icons.pause_circle_filled_rounded);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;

  setUpAll(() async {
    await QueueCrypto.encryptPayload('{}');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('lan_pause_exit_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    HeartbeatService.instance.cancelTest(); // clean pause baseline
  });

  tearDown(() async {
    HeartbeatService.instance.cancelTest();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  testWidgets(
      'kiosk inactivity timeout does not pull a paused student out of the test',
      (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, __) => const Text('login')),
      GoRoute(path: '/engine', builder: (_, __) => _engine()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(InactivityWrapper(
      router: router,
      timeout: const Duration(minutes: 30),
      child: MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    ));
    router.go('/engine');
    await tester.pump();
    await _settle(tester);

    HeartbeatService.instance.reconcileProctorState(locked: true);
    await tester.pump();
    expect(_shield, findsOneWidget);

    await tester.pump(const Duration(minutes: 31)); // nobody touches the PC
    await _settle(tester); // CredentialCache.clear() runs on the real loop
    await tester.pump(const Duration(milliseconds: 500));

    expect(
        router.routerDelegate.currentConfiguration.uri.toString(), '/engine');
    expect(_shield, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('leaving the engine keeps the attempt for the next entry',
      (tester) async {
    await tester.pumpWidget(_app(_engine()));
    await _settle(tester);
    expect(await tester.runAsync(() => AttemptStore.load(_testKey)), isNotNull);

    await tester.pumpWidget(const SizedBox()); // route removed without finish
    await _settle(tester);

    final saved = await tester.runAsync(() => AttemptStore.load(_testKey));
    expect(saved, isNotNull, reason: 'attempt must survive leaving');
  });

  testWidgets(
      'pause persisted: re-entering after the stale deadline has passed stays '
      'paused-safe and keeps the remaining time (no auto-submit, no reset)',
      (tester) async {
    final past = DateTime.now()
        .subtract(const Duration(minutes: 20))
        .millisecondsSinceEpoch;
    await tester.runAsync(() => AttemptStore.save(
        _testKey, _record(deadlineMs: past, pausedRemainingMs: 300000)));

    var expired = 0;
    var done = 0;
    await tester.pumpWidget(
        _app(_engine(onExpired: () => expired++, onComplete: () => done++)));
    await _settle(tester);

    expect(expired, 0);
    expect(done, 0);
    expect(find.text('05:00'), findsOneWidget,
        reason: 'frozen remaining time, not 10:00 and not 00:00');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('hub says the attempt is still paused: shield is up on re-entry',
      (tester) async {
    final future =
        DateTime.now().add(const Duration(minutes: 4)).millisecondsSinceEpoch;
    await tester.runAsync(() => AttemptStore.save(
        _testKey, _record(deadlineMs: future, pausedRemainingMs: 240000)));
    // startTest()'s first ping already carried locked:true (no engine yet).
    HeartbeatService.instance.reconcileProctorState(locked: true);

    await tester.pumpWidget(_app(_engine()));
    await _settle(tester);
    await _settle(tester); // restore -> persist -> pause hop

    expect(_shield, findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('abandoning the engine tells the hub (test session is closed)',
      (tester) async {
    await tester.runAsync(() => HeartbeatService.instance.startTest(
        schoolCode: '56',
        name: 'Ism Familiya',
        variant: '1',
        testKey: _testKey,
        studentCode: _student));
    expect(HeartbeatService.instance.activeSessionId, isNotNull);

    await tester.pumpWidget(_app(_engine()));
    await _settle(tester);
    await tester.pumpWidget(const SizedBox());
    await _settle(tester);

    expect(HeartbeatService.instance.activeSessionId, isNull,
        reason: 'ghost test session would keep pinging as in-test');
  });

  test('startTest reuses the attempt id as the hub session id', () async {
    await HeartbeatService.instance.startTest(
        schoolCode: '56',
        name: 'x',
        variant: '1',
        testKey: _testKey,
        studentCode: _student,
        sessionId: 'attempt-xyz');
    expect(HeartbeatService.instance.activeSessionId, 'attempt-xyz');
  });

  test('re-entering an unfinished attempt never mints a fresh timer/attempt',
      () async {
    SharedPreferences.setMockInitialValues({});
    final past = DateTime.now()
        .subtract(const Duration(minutes: 5))
        .millisecondsSinceEpoch;
    final id = newIdempotencyToken();
    await AttemptStore.save(_testKey, _record(deadlineMs: past, attemptId: id));

    final v = await resolveAttemptVariant(
      {
        'variants': {'1': {}, '2': {}, '3': {}}
      },
      testKey: _testKey,
      firstName: 'Ism',
      lastName: 'Familiya',
      studentId: _student,
      groupName: '',
    );
    final after = await AttemptStore.load(_testKey);
    expect(v, 1);
    expect(after?['attempt_id'], id);
    expect(after?['deadline_epoch_ms'], past);
    MonitoredClock.instance.stopMonitoring();
  });
}
