// Audit wave 2 #3: RTC/clock guards in MonitoredClock.rebaseSavedDeadline for
// a restart on a DIFFERENT boot (power cut + dead CMOS battery, clock reset).
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

const _min = 60 * 1000;
const _day = 24 * 60 * _min;

/// A clock for a fresh boot (ticks restarted low) reading [wall].
MonitoredClock _rebooted(int wall) => MonitoredClock(
    ticks: () => 5000, wall: () => wall, highWaterStore: _MemHwm());

void main() {
  final saveWall = DateTime.utc(2026, 10, 17, 9).millisecondsSinceEpoch;
  const saveTicks = 90 * 60 * _min; // long uptime before the cut -> reboot
  final deadline = saveWall + 20 * _min; // 20 min were left at save

  int rebase(MonitoredClock c) => c.rebaseSavedDeadline(
        deadlineEpochMs: deadline,
        epochAtSaveMs: saveWall,
        ticksAtSaveMs: saveTicks,
      );

  test('(a) clock reset to 1970 after power cut keeps the remaining time', () {
    final c = _rebooted(0);
    final rebased = rebase(c);
    expect(rebased - c.nowMs, 20 * _min); // not 56 years
  });

  test('(a) clock moved back to 2000 keeps the remaining time', () {
    final c = _rebooted(DateTime.utc(2000, 1, 1).millisecondsSinceEpoch);
    expect(rebase(c) - c.nowMs, 20 * _min);
  });

  test('(a) small backward drift (<= 60 s) is ordinary clock noise', () {
    final c = _rebooted(saveWall - 30 * 1000);
    expect(rebase(c), deadline); // stored epoch deadline unchanged
  });

  test('normal reboot: power-off time still counts', () {
    final c = _rebooted(saveWall + 5 * _min);
    expect(rebase(c), deadline);
    expect(rebase(c) - c.nowMs, 15 * _min);
  });

  test('absence beyond remaining time but within a day: honest expiry', () {
    final c = _rebooted(saveWall + 3 * 60 * _min); // 3 h later
    expect(rebase(c) - c.nowMs, lessThan(0)); // deadline passed -> auto-submit
  });

  test(
      '(b) wall clock ahead by more than remaining + 1 day is a bogus jump: '
      'remaining time recorded at save is kept, no instant expiry', () {
    final c = _rebooted(saveWall + 20 * _min + _day + 1);
    expect(rebase(c) - c.nowMs, 20 * _min);
  });

  test('(b) exactly at the 1-day margin is still honest expiry', () {
    final c = _rebooted(saveWall + 20 * _min + _day);
    expect(rebase(c) - c.nowMs, lessThan(0));
  });

  test('legacy record without snapshot is unchanged', () {
    final c = _rebooted(0);
    expect(c.rebaseSavedDeadline(deadlineEpochMs: deadline), deadline);
  });
}
