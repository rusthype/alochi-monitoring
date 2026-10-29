// Audit wave 3 (P1-1 / P2-3): resolveAttemptVariant must never replace a saved
// attempt that holds answers, and its resume/stale decision must follow the
// engine's trusted (rebased) clock, not the raw wall clock.
import 'dart:io';

import 'package:alochi_monitoring/core/db/attempt_store.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/features/session/runner_dispatch.dart'
    show resolveAttemptVariant;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

const _min = 60 * 1000;
const _day = 24 * 60 * _min;
const _key = 'dispatch_resume_v1';
const _student = 'S-9';

Future<int> _resolve() => resolveAttemptVariant(
      {
        'variants': {'1': {}, '2': {}, '3': {}}
      },
      testKey: _key,
      firstName: 'Ism',
      lastName: 'Familiya',
      studentId: _student,
      groupName: '',
    );

Map<String, dynamic> _rec({
  required int deadline,
  Map<String, dynamic>? answers,
  Map<String, int>? snapshot,
}) =>
    {
      'variant': 2,
      'answers': answers ?? <String, dynamic>{},
      'started_at': deadline - 40 * _min,
      'attempt_id': 'nonce-1',
      'deadline_epoch_ms': deadline,
      ...?snapshot,
      'student_name': 'Ism Familiya',
      'student_id': _student,
      'group_name': '',
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late MonitoredClock saved;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await QueueCrypto.encryptPayload('{}');
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('dispatch_resume_');
    AttemptStore.useDirectoryForTest(tmp);
    saved = MonitoredClock.instance;
  });
  tearDown(() {
    MonitoredClock.instance = saved;
    AttemptStore.useDirectoryForTest(null);
    tmp.deleteSync(recursive: true);
  });

  test('an attempt with answers abandoned for days is resumed, never replaced',
      () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await AttemptStore.save(
        _key, _rec(deadline: now - 3 * _day, answers: {'Math/0': 1}));

    expect(await _resolve(), 2);

    final after = await AttemptStore.load(_key);
    expect(after!['attempt_id'], 'nonce-1');
    expect(after['answers'], {'Math/0': 1});
  });

  test('an EMPTY long-abandoned seed is replaced by a fresh attempt', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await AttemptStore.save(_key, _rec(deadline: now - 3 * _day));

    await _resolve();

    final after = await AttemptStore.load(_key);
    expect(after!['attempt_id'], isNot('nonce-1'));
  });

  test(
      'dead CMOS: the engine timeline is in 2000 while the wall clock was '
      'stepped to 2026 - a live attempt is not "stale"', () async {
    var wall = DateTime.utc(2000, 1, 1).millisecondsSinceEpoch;
    var ticks = 5 * _min;
    final clock = MonitoredClock(
        ticks: () => ticks, wall: () => wall, highWaterStore: _MemHwm());
    MonitoredClock.instance = clock;
    // The attempt started (and was saved) on that 2000-based timeline.
    await AttemptStore.save(_key,
        _rec(deadline: clock.nowMs + 5 * _min, snapshot: clock.snapshot()));
    // 3 h later by the monotonic clock NTP steps the wall clock to 2026.
    ticks += 3 * 60 * _min;
    wall = DateTime.utc(2026, 10, 29).millisecondsSinceEpoch;

    // The raw wall clock calls the record ~26 years stale; the trusted
    // timeline says its deadline passed ~3 h ago (< 12 h): resumed.
    expect(await _resolve(), 2);
    expect((await AttemptStore.load(_key))!['attempt_id'], 'nonce-1');
  });
}
