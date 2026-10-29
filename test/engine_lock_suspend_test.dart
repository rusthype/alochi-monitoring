// Audit wave 7 (P2-1): a teacher lock (pause) and a PC suspend overlapping.
// With the server as witness `absorbSuspend()` no longer credits a jump at
// once: the verdict arrives later. Pause/resume must drop that pending
// verdict, otherwise the slept time is taken from (resume) or handed to
// (pause) the student, who is not responsible for it either way.
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/core/services/heartbeat_service.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _testKey = 'engine_lock_suspend_v1';
const _student = '00000000-0000-4000-8000-0000000000d2';
const _min = 60 * 1000;

class _NoHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

/// Device ticks / wall and a server that only follows real time.
class _World {
  int ticks = 5000000;
  int wall = DateTime.utc(2026, 10, 29, 9).millisecondsSinceEpoch;
  int server = DateTime.utc(2026, 10, 29, 9).millisecondsSinceEpoch;
  int seq = 0;
  int? offset;

  void observe() {
    offset = server - wall;
    seq++;
  }

  /// The PC slept [ms]: ticks frozen, wall and server moved on.
  void sleep(int ms) {
    wall += ms;
    server += ms;
  }

  MonitoredClock clock() => MonitoredClock(
        ticks: () => ticks,
        wall: () => wall,
        highWaterStore: _NoHwm(),
        serverSample: () => offset == null ? null : (offsetMs: offset!, seq: seq),
        probeServer: () {}, // the answer is delivered by hand
      );
}

Widget _engine({VoidCallback? onExpired}) => TestEngine(
      spec: TestSpec.fromJson({
        'test_key': _testKey,
        'title': 'Lock suspend',
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
      }),
      variant: 1,
      firstName: 'Ism',
      lastName: 'Familiya',
      school: '56',
      studentId: _student,
      duration: const Duration(minutes: 10),
      onComplete: (_, __) {},
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
  late MonitoredClock realClock;

  setUpAll(() async {
    await QueueCrypto.encryptPayload('{}');
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = Directory.systemTemp.createTempSync('engine_lock_suspend_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    HeartbeatService.instance.cancelTest();
    realClock = MonitoredClock.instance;
  });

  tearDown(() async {
    MonitoredClock.instance.stopMonitoring();
    MonitoredClock.instance = realClock;
    HeartbeatService.instance.cancelTest();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  testWidgets('lock, then the PC sleeps: resume gives back the paused time',
      (tester) async {
    final w = _World()..observe();
    MonitoredClock.instance = w.clock();
    var expired = 0;
    await tester.pumpWidget(_app(_engine(onExpired: () => expired++)));
    await _settle(tester);
    expect(find.text('10:00'), findsOneWidget);

    HeartbeatService.instance.reconcileProctorState(locked: true);
    await tester.pump();
    expect(_shield, findsOneWidget);

    w.sleep(20 * _min); // lid closed while the test is paused
    HeartbeatService.instance.reconcileProctorState(locked: false);
    await tester.pump();
    expect(_shield, findsNothing);
    expect(find.text('10:00'), findsOneWidget);

    // The server's answer to the probe arrives AFTER the resume: it must not
    // charge the paused sleep to the student.
    w.observe();
    await tester.pump(const Duration(seconds: 2));
    expect(expired, 0);
    expect(find.text('10:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the PC sleeps, then a lock arrives: paused time is not eaten',
      (tester) async {
    final w = _World()..observe();
    MonitoredClock.instance = w.clock();
    var expired = 0;
    await tester.pumpWidget(_app(_engine(onExpired: () => expired++)));
    await _settle(tester);
    expect(find.text('10:00'), findsOneWidget);

    w.sleep(20 * _min); // lid closed, then the teacher's lock lands on wake
    HeartbeatService.instance.reconcileProctorState(locked: true);
    await tester.pump();
    expect(_shield, findsOneWidget);
    HeartbeatService.instance.reconcileProctorState(locked: false);
    await tester.pump();
    expect(find.text('10:00'), findsOneWidget);

    w.observe(); // the late verdict must not land inside the resumed test
    await tester.pump(const Duration(seconds: 2));
    expect(expired, 0);
    expect(find.text('10:00'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
