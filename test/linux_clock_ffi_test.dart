// Linux-only: the REAL clock_gettime(CLOCK_BOOTTIME) behind platformTicksMs.
import 'dart:io';

import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';

double _uptimeMs() =>
    double.parse(File('/proc/uptime').readAsStringSync().split(' ').first) *
    1000;

void main() {
  final skip = Platform.isLinux ? false : 'Linux only (CLOCK_BOOTTIME)';

  test('ticks are since-boot: within a few ms of /proc/uptime', () {
    final before = _uptimeMs();
    final t = platformTicksMs();
    final after = _uptimeMs();
    // /proc/uptime has 10 ms resolution; allow slack for it.
    expect(t, inInclusiveRange(before - 20, after + 20));
    // A Stopwatch fallback would be near 0 in a fresh test process.
    expect(t, greaterThan(60 * 1000),
        reason: 'looks like the Stopwatch fallback');
  }, skip: skip);

  test('monotonic over many calls and tracks real time', () async {
    var prev = platformTicksMs();
    for (var i = 0; i < 50000; i++) {
      final t = platformTicksMs();
      expect(t, greaterThanOrEqualTo(prev));
      prev = t;
    }
    final sw = Stopwatch()..start();
    final t0 = platformTicksMs();
    await Future<void>.delayed(const Duration(milliseconds: 600));
    final dTicks = platformTicksMs() - t0;
    expect((dTicks - sw.elapsedMilliseconds).abs(), lessThan(150));
  }, skip: skip);
}
