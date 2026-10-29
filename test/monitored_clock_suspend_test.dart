// MonitoredClock.absorbSuspend: slept time (ticks frozen, wall advanced) is
// credited once; a backward wall jump, a clock-reset-sized jump and NTP-slew
// sized drift never add or remove time.
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';

class _NoHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

class _Fake {
  int ticks = 5000000;
  int wall = DateTime.utc(2026, 10, 17, 9).millisecondsSinceEpoch;
  void advance(int ms) {
    ticks += ms;
    wall += ms;
  }

  MonitoredClock clock() =>
      MonitoredClock(ticks: () => ticks, wall: () => wall, highWaterStore: _NoHwm());
}

void main() {
  test('suspend: ticks frozen, wall +10 min -> nowMs moves by 10 min, once',
      () {
    final f = _Fake();
    final c = f.clock();
    f.advance(30000);
    expect(c.absorbSuspend(), 0);
    final before = c.nowMs;

    f.wall += 10 * 60 * 1000; // lid closed
    expect(c.absorbSuspend(), 10 * 60 * 1000);
    expect(c.nowMs - before, 10 * 60 * 1000);

    f.advance(1000);
    expect(c.absorbSuspend(), 0, reason: 'no double credit');
    expect(c.nowMs - before, 10 * 60 * 1000 + 1000);
  });

  test('several suspends add up; ticks that already include the sleep add '
      'nothing', () {
    final f = _Fake();
    final c = f.clock();
    final t0 = c.nowMs;
    f.wall += 60000;
    c.absorbSuspend();
    f.advance(2000);
    f.wall += 90000;
    c.absorbSuspend();
    expect(c.nowMs - t0, 60000 + 2000 + 90000);

    // Windows-style: ticks keep counting through sleep -> no disagreement.
    final g = _Fake();
    final d = g.clock();
    final u0 = d.nowMs;
    g.advance(15 * 60 * 1000);
    expect(d.absorbSuspend(), 0);
    expect(d.nowMs - u0, 15 * 60 * 1000);
  });

  test('wall clock set BACK never adds time, and does not poison later ticks',
      () {
    final f = _Fake();
    final c = f.clock();
    f.advance(1000);
    final before = c.nowMs;
    f.wall -= 3 * 3600 * 1000;
    expect(c.absorbSuspend(), 0);
    expect(c.nowMs, before);
    f.advance(5000);
    expect(c.absorbSuspend(), 0);
    expect(c.nowMs - before, 5000);
  });

  test('NTP-sized adjustments inside the tolerance change nothing', () {
    final f = _Fake();
    final c = f.clock();
    final t0 = c.nowMs;
    f.advance(60000);
    f.wall += 3000; // NTP step / slew
    expect(c.absorbSuspend(), 0);
    f.wall -= 4000;
    expect(c.absorbSuspend(), 0);
    expect(c.nowMs - t0, 60000);
  });

  test('a reset-sized forward jump (dead CMOS fixed by NTP) is not credited',
      () {
    final f = _Fake();
    final c = f.clock();
    final t0 = c.nowMs;
    f.wall += 26 * 365 * 86400 * 1000;
    expect(c.absorbSuspend(), 0);
    expect(c.nowMs, t0);
  });

  test('idle time before a test starts is not charged to it', () {
    final f = _Fake();
    final c = f.clock();
    f.wall += 2 * 3600 * 1000; // laptop slept on the login screen
    c.startMonitoring(); // engine opens
    addTearDown(c.stopMonitoring);
    final start = c.nowMs;
    f.advance(1000);
    expect(c.absorbSuspend(), 0);
    expect(c.nowMs - start, 1000);
  });
}
