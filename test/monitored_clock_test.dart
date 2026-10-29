// MonitoredClock: skew detection, high-water mark, resume rebase and the
// TestEngine's resistance to the system date being changed mid-test.
import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/engine/test_engine.dart';
import 'package:alochi_monitoring/core/engine/test_models.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemHwm implements HighWaterStore {
  DateTime? value;
  _MemHwm([this.value]);
  @override
  Future<DateTime?> read() async => value;
  @override
  Future<void> write(DateTime utc) async => value = utc;
}

class _Fake {
  int ticks = 1000000;
  int wall = DateTime.utc(2026, 10, 17, 9).millisecondsSinceEpoch;
  void advance(int ms) {
    ticks += ms;
    wall += ms;
  }

  MonitoredClock clock({_MemHwm? hwm}) => MonitoredClock(
        ticks: () => ticks,
        wall: () => wall,
        highWaterStore: hwm ?? _MemHwm(),
      );
}

/// QueueCrypto/AttemptStore talk to flutter_secure_storage + path_provider.
/// Without handlers those platform calls only complete on the REAL event loop,
/// so the engine's restore would finish outside the fake-async zone and its
/// Timer.periodic would not be driven by tester.pump. Answering them here
/// keeps everything on microtasks.
void _mockPlatformChannels(WidgetTester tester) {
  final m = tester.binding.defaultBinaryMessenger;
  const secure = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  final store = <String, String>{};
  m.setMockMethodCallHandler(secure, (call) async {
    final key = (call.arguments as Map?)?['key'] as String?;
    switch (call.method) {
      case 'write':
        store[key!] = (call.arguments as Map)['value'] as String;
        return null;
      case 'read':
        return store[key];
      default:
        return null;
    }
  });
  m.setMockMethodCallHandler(paths, (call) async => Directory.systemTemp.path);
  addTearDown(() {
    m.setMockMethodCallHandler(secure, null);
    m.setMockMethodCallHandler(paths, null);
  });
}

/// QueueCrypto caches its key Future process-wide. Resolve it on the REAL
/// event loop first; if it were created inside one test's fake-async zone and
/// left pending, a later test awaiting it would hang forever.
Future<void> _warmQueueCrypto(WidgetTester tester) async {
  await tester.runAsync(() => QueueCrypto.encryptPayload('warm'));
}

/// Lets the engine's async attempt restore (prefs + crypto key) finish.
Future<void> _settle(WidgetTester tester) async {
  await tester
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await tester.pump();
}

void main() {
  group('skew detection', () {
    test('normal passage of time raises no flag', () {
      final f = _Fake();
      final c = f.clock();
      for (var i = 0; i < 12; i++) {
        f.advance(5000);
        c.checkNow();
      }
      expect(c.drainFlags(), isEmpty);
    });

    test('small drift (<=5s) is tolerated', () {
      final f = _Fake();
      final c = f.clock();
      f.advance(5000);
      f.wall += 4000;
      c.checkNow();
      expect(c.drainFlags(), isEmpty);
    });

    test('wall clock set forward 1h -> clock_forward flag, nowMs unchanged',
        () {
      final f = _Fake();
      final c = f.clock();
      final before = c.nowMs;
      f.advance(5000);
      f.wall += 3600000; // user edits the date
      c.checkNow();
      final flags = c.drainFlags();
      expect(flags, hasLength(1));
      expect(flags.single['type'], 'clock_forward');
      expect(flags.single['skew_ms'], 3600000);
      // Trusted time only moved by the real 5s.
      expect(c.nowMs - before, 5000);
      // Drained: a second drain is empty, and the next window is clean.
      expect(c.drainFlags(), isEmpty);
      f.advance(5000);
      c.checkNow();
      expect(c.drainFlags(), isEmpty);
    });

    test('wall clock set back -> clock_backward flag', () {
      final f = _Fake();
      final c = f.clock();
      f.advance(5000);
      f.wall -= 2 * 3600000;
      c.checkNow();
      final flags = c.drainFlags();
      expect(flags.single['type'], 'clock_backward');
      expect(flags.single['skew_ms'], -2 * 3600000);
    });
  });

  group('high-water mark', () {
    test('clock behind the stored mark is flagged and mark is kept', () async {
      final f = _Fake();
      final hwm = _MemHwm(
          DateTime.fromMillisecondsSinceEpoch(f.wall + 86400000, isUtc: true));
      final c = f.clock(hwm: hwm);
      await c.checkHighWaterMark();
      final flags = c.drainFlags();
      expect(flags.single['type'], 'clock_before_high_water_mark');
      expect(hwm.value!.millisecondsSinceEpoch, f.wall + 86400000);
    });

    test('clock ahead of the mark advances it, no flag', () async {
      final f = _Fake();
      final hwm = _MemHwm(
          DateTime.fromMillisecondsSinceEpoch(f.wall - 1000, isUtc: true));
      final c = f.clock(hwm: hwm);
      await c.checkHighWaterMark();
      expect(c.drainFlags(), isEmpty);
      expect(hwm.value!.millisecondsSinceEpoch, f.wall);
    });

    test('clock before pack created_at is flagged', () async {
      final f = _Fake();
      final c = f.clock();
      c.packCreatedAt =
          DateTime.fromMillisecondsSinceEpoch(f.wall + 1000, isUtc: true);
      await c.checkHighWaterMark();
      expect(c.drainFlags().single['type'], 'clock_before_pack_created');
    });
  });

  group('resume rebase', () {
    test('same boot: date moved back while closed does not change remaining',
        () {
      final f1 = _Fake();
      final c1 = f1.clock();
      final deadline = c1.nowMs + 600000; // 10 min
      final snap = c1.snapshot();
      // 60s later (real), the process restarts and the user moved the date -5h.
      final f2 = _Fake()
        ..ticks = f1.ticks + 60000
        ..wall = f1.wall - 5 * 3600000;
      final c2 = f2.clock();
      final rebased = c2.rebaseSavedDeadline(
        deadlineEpochMs: deadline,
        epochAtSaveMs: snap['epoch_at_save'],
        ticksAtSaveMs: snap['ticks_at_save'],
      );
      expect(rebased - c2.nowMs, 540000); // exactly 9 min left
    });

    test('same boot: date moved forward while closed never adds time', () {
      // Contract change (audit wave 3): a forward date change used to be
      // ignored (ticks only). With no boot id that is indistinguishable from
      // a reboot with a longer uptime, which regained the downtime; the
      // larger elapsed now wins.
      final f1 = _Fake();
      final c1 = f1.clock();
      final deadline = c1.nowMs + 600000;
      final snap = c1.snapshot();
      final f2 = _Fake()
        ..ticks = f1.ticks + 60000
        ..wall = f1.wall + 5 * 3600000;
      final c2 = f2.clock();
      final rebased = c2.rebaseSavedDeadline(
        deadlineEpochMs: deadline,
        epochAtSaveMs: snap['epoch_at_save'],
        ticksAtSaveMs: snap['ticks_at_save'],
      );
      expect(rebased - c2.nowMs, lessThan(0));
    });

    test('reboot (ticks went backwards) falls back to the stored deadline', () {
      final f = _Fake()..ticks = 5000;
      final c = f.clock();
      // Saved 5 min before "now" with 20 min left: a plausible power cut.
      final saved = f.wall - 5 * 60000;
      final rebased = c.rebaseSavedDeadline(
        deadlineEpochMs: saved + 20 * 60000,
        epochAtSaveMs: saved,
        ticksAtSaveMs: 9999999,
      );
      expect(rebased, saved + 20 * 60000);
    });

    test('legacy record without snapshot is unchanged', () {
      final c = _Fake().clock();
      expect(c.rebaseSavedDeadline(deadlineEpochMs: 42), 42);
    });
  });

  group('TestEngine', () {
    Map<String, dynamic> specJson() => {
          'test_key': 'clock_test_v1',
          'title': 'Clock Test',
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

    testWidgets(
        'changing the system date +1h mid-test neither ends the test nor '
        'moves the countdown, and records a clock flag', (tester) async {
      SharedPreferences.setMockInitialValues({});
      _mockPlatformChannels(tester);
      await _warmQueueCrypto(tester);
      final f = _Fake();
      final saved = MonitoredClock.instance;
      MonitoredClock.instance = f.clock();
      addTearDown(() => MonitoredClock.instance = saved);

      var completed = false;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TestEngine(
          spec: TestSpec.fromJson(specJson()),
          variant: 1,
          firstName: 'Ism',
          lastName: 'Familiya',
          school: '56',
          studentId: 'S-CLOCK-1',
          duration: const Duration(minutes: 10),
          onComplete: (_, __) => completed = true,
        ),
      ));
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await _settle(tester);

      // Drives the engine's countdown deterministically: the lifecycle
      // `resumed` hook runs the same _syncSecsFromDeadline() the 1s Timer does,
      // without depending on which zone the restore chain created that Timer in.
      Future<void> step(int seconds) async {
        for (var i = 0; i < seconds; i++) {
          f.ticks += 1000;
          f.wall += 1000;
          tester.binding
              .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
          await tester.pump();
        }
        MonitoredClock.instance.checkNow();
      }

      await step(3);
      expect(find.text('09:57'), findsOneWidget);

      // The student sets the date one hour forward. Ticks do not move.
      f.wall += 3600000;
      await step(3); // crosses a 5s skew-check boundary

      expect(completed, isFalse,
          reason: 'wall-clock jump must not end the test');
      expect(find.text('09:54'), findsOneWidget);
      final flags = MonitoredClock.instance.drainFlags();
      expect(flags.any((x) => x['type'] == 'clock_forward'), isTrue);

      // Same jump backwards must not add time either.
      f.wall -= 2 * 3600000;
      await step(2);
      expect(find.text('09:52'), findsOneWidget);
    });

    testWidgets(
        'resume after restart: remaining comes from ticks, not the date',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      _mockPlatformChannels(tester);
      await _warmQueueCrypto(tester);
      const testKey = 'clock_test_v1';
      final f1 = _Fake();
      final c1 = f1.clock();
      // Attempt saved by "the previous process": 10 min deadline, 60s used.
      await tester.runAsync(() => AttemptStore.save(testKey, {
            'variant': 1,
            'answers': <String, dynamic>{},
            'started_at': c1.nowMs - 60000,
            'deadline_epoch_ms': c1.nowMs + 540000,
            ...c1.snapshot(),
            'student_name': 'Ism Familiya',
            'student_id': 'S-CLOCK-2',
            'group_name': '',
          }));
      // New process, same boot, 30s later; the date was moved -3h meanwhile.
      final f2 = _Fake()
        ..ticks = f1.ticks + 30000
        ..wall = f1.wall - 3 * 3600000;
      final saved = MonitoredClock.instance;
      MonitoredClock.instance = f2.clock();
      addTearDown(() => MonitoredClock.instance = saved);

      var completed = false;
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TestEngine(
          spec: TestSpec.fromJson(specJson()),
          variant: 1,
          firstName: 'Ism',
          lastName: 'Familiya',
          school: '56',
          studentId: 'S-CLOCK-2',
          duration: const Duration(minutes: 10),
          onComplete: (_, __) => completed = true,
        ),
      ));
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await _settle(tester);

      expect(completed, isFalse);
      // 540s - 30s = 510s = 08:30
      expect(find.text('08:30'), findsOneWidget);
    });
  });
}
