// "Finish the test" from the teacher's LAN hub must end the student's test in
// seconds (the 2.5 s frame reply, not only the 30 s ping), also while paused,
// also right after re-entering the same attempt, and exactly once. Real hub +
// LanClientApi on loopback; the engine's own ProctorService drives the frame
// channel (dev machines are macOS: capture is mocked there).
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/lan_client_api.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/core/services/heartbeat_service.dart';
import 'package:alochi_monitoring/core/services/proctor_service.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/io_client.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/lan_test_pack.dart';

const _testKey = 'lan_term_v1';
const _attempt = 'attempt-term-1';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

Map<String, dynamic> _specJson() => {
      'test_key': _testKey,
      'title': 'Term test',
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

Map<String, dynamic> _record() => {
      'variant': 1,
      'answers': <String, dynamic>{'Math/0': 1},
      'started_at': DateTime.now().millisecondsSinceEpoch,
      'attempt_id': _attempt,
      'deadline_epoch_ms':
          DateTime.now().add(const Duration(minutes: 9)).millisecondsSinceEpoch,
      'student_name': 'Ism Familiya',
      'student_id': lanS1,
      'group_name': '',
    };

final _shield = find.byIcon(Icons.pause_circle_filled_rounded);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final clockWatch = Stopwatch()..start(); // frame rate limit needs real time
  late Directory tmp;
  late ShelfHub hub;
  late LanClientSession session;
  late MonitoringApi parked;

  setUpAll(() async {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    await QueueCrypto.encryptPayload('{}');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('lan_term_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    final pack = await OfflinePackSession.open(
        lanTestPack(), Directory(p.join(tmp.path, 'media')));
    hub = ShelfHub(pack,
        bindAddress: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
        clock: MonitoredClock(
            ticks: () => clockWatch.elapsedMilliseconds + 1000000,
            wall: () => 0,
            highWaterStore: _MemHwm()));
    await hub.start(announce: false);
    session = await LanClientSession.join(
      host: '127.0.0.1',
      port: hub.port!,
      code: hub.state!.code,
      // No keep-alive: its 15 s idle timer would outlive the fake-async zone.
      client: IOClient(HttpClient()..idleTimeout = Duration.zero),
      machineId: 'pc-1',
      deviceName: 'PC',
      mediaDirFor: (id) async => Directory(p.join(tmp.path, 'cm', id)),
    );
    parked = api;
    api = LanClientApi(session);
    HeartbeatService.instance.cancelTest();
  });

  tearDown(() async {
    ProctorService.instance.stop();
    HeartbeatService.instance.cancelTest();
    HeartbeatService.instance.onTerminated = null;
    api = parked;
    session.close();
    await hub.stop();
    hub.dispose();
    OfflinePackSession.close();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<void> startAttempt() => HeartbeatService.instance.startTest(
      schoolCode: '999',
      name: 'Ism Familiya',
      variant: '1',
      testKey: _testKey,
      studentCode: lanS1,
      sessionId: _attempt);

  int hubId() => hub.state!.views().single.id;

  Widget engine(void Function() onComplete) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TestEngine(
          spec: TestSpec.fromJson(_specJson()),
          variant: 1,
          firstName: 'Ism',
          lastName: 'Familiya',
          school: '999',
          studentId: lanS1,
          duration: const Duration(minutes: 10),
          onComplete: (_, __) => onComplete(),
        ),
      );

  /// Waits (real time) until [done] or [within] elapses; returns the seconds.
  Future<double> waitFor(WidgetTester tester, bool Function() done,
      {Duration within = const Duration(seconds: 9)}) async {
    final sw = Stopwatch()..start();
    while (!done() && sw.elapsed < within) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    return sw.elapsedMilliseconds / 1000;
  }

  /// Unmounts and drops the client's keep-alive sockets (their 15 s timers
  /// would otherwise outlive the fake-async test zone).
  Future<void> leave(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    session.close();
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 200)));
    await tester.pump(const Duration(seconds: 3)); // close() timers
  }

  Future<void> mount(WidgetTester tester, void Function() onComplete) async {
    await tester.runAsync(() => AttemptStore.save(_testKey, _record()));
    await tester.runAsync(startAttempt);
    await tester.pumpWidget(engine(onComplete));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('frame channel: terminate ends the test within seconds, once',
      (tester) async {
    var done = 0;
    await mount(tester, () => done++);
    hub.state!.terminate(hubId());

    final took = await waitFor(tester, () => done > 0);
    expect(done, 1, reason: 'not finished after ${took}s (ping is 30s)');
    expect(took, lessThan(8));
    // Both channels keep reporting it: still exactly one submit.
    await waitFor(tester, () => false, within: const Duration(seconds: 3));
    expect(done, 1);
    await leave(tester);
  });

  testWidgets('paused student: terminate still ends the test', (tester) async {
    var done = 0;
    await mount(tester, () => done++);
    hub.state!.setLocked(hubId(), true);
    await waitFor(tester, () => _shield.evaluate().isNotEmpty);
    expect(_shield, findsOneWidget);

    hub.state!.terminate(hubId());
    await waitFor(tester, () => done > 0);
    expect(done, 1);
    await leave(tester);
  });

  testWidgets('re-entry of the same attempt after terminate still finishes',
      (tester) async {
    var done = 0;
    await mount(tester, () => done++);
    await tester.pumpWidget(const SizedBox()); // student left (hub: abandoned)
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.runAsync(startAttempt); // re-claims the same attempt id
    hub.state!.terminate(hubId());

    await tester.pumpWidget(engine(() => done++)); // re-enter
    await waitFor(tester, () => done > 0);
    expect(done, 1);
    await leave(tester);
  });
}
