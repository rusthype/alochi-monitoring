// Security review F3: moving the date FORWARD once must not poison the
// persisted high-water mark (it feeds pack expiry via trustedNowUtc), while an
// honest gap while the app was closed still advances it and the set-back
// protection (wave 9a) keeps working.
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemHwm implements HighWaterStore {
  DateTime? value;
  _MemHwm([this.value]);
  @override
  Future<DateTime?> read() async => value;
  @override
  Future<void> write(DateTime utc) async => value = utc;
}

const _day = 24 * 3600 * 1000;
final _t0 = DateTime.utc(2026, 10, 17, 9).millisecondsSinceEpoch;

class _Fake {
  int ticks = 1000000;
  int wall = _t0;
  void advance(int ms) {
    ticks += ms;
    wall += ms;
  }

  MonitoredClock clock(_MemHwm hwm, {ServerSample? server}) => MonitoredClock(
        ticks: () => ticks,
        wall: () => wall,
        highWaterStore: hwm,
        serverSample: () => server,
        serverSource: () => 'cloud',
      );
}

DateTime _utc(int ms) => DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('+1 year mid-run does not make a pack expiring in 30 days look expired',
      () async {
    final f = _Fake();
    final hwm = _MemHwm(_utc(_t0));
    final c = f.clock(hwm);
    await c.checkHighWaterMark();

    f.advance(60 * 1000); // an ordinary minute
    c.checkNow();
    await _settle();

    // The student jumps the date a year ahead, stays long enough for a write.
    f.ticks += 61 * 1000;
    f.wall += 365 * _day;
    c.checkNow();
    await _settle();
    f.wall -= 365 * _day; // and puts it back

    expect(hwm.value!.millisecondsSinceEpoch, lessThan(_t0 + 3600 * 1000));
    final packExpiry = _utc(_t0 + 30 * _day);
    expect((await c.trustedNowUtc()).isBefore(packExpiry), isTrue);
  });

  test('the mark follows honest time in-process', () async {
    final f = _Fake();
    final hwm = _MemHwm(_utc(_t0));
    final c = f.clock(hwm);
    await c.checkHighWaterMark();
    f.advance(10 * 60 * 1000);
    c.checkNow();
    await _settle();
    expect(hwm.value!.millisecondsSinceEpoch, f.wall);
  });

  test('honest 3-day gap while the app was closed advances the mark', () async {
    final hwm = _MemHwm(_utc(_t0));
    final f = _Fake()..wall = _t0 + 3 * _day;
    final c = f.clock(hwm);
    await c.checkHighWaterMark();
    expect(c.drainFlags(), isEmpty);
    expect(hwm.value!.millisecondsSinceEpoch, _t0 + 3 * _day);
  });

  test(
      'cold start 1 year ahead: unconfirmed jump is flagged and capped at 30 d',
      () async {
    final hwm = _MemHwm(_utc(_t0));
    final f = _Fake()..wall = _t0 + 365 * _day;
    final c = f.clock(hwm);
    await c.checkHighWaterMark();
    expect(hwm.value!.millisecondsSinceEpoch, _t0 + 30 * _day);
    expect(c.drainFlags().map((e) => e['type']),
        contains('clock_forward_unconfirmed'));

    // Still capped (plus elapsed ticks only) a minute later in the same run.
    f.advance(61 * 1000);
    c.checkNow();
    await _settle();
    expect(hwm.value!.millisecondsSinceEpoch,
        lessThanOrEqualTo(_t0 + 30 * _day + 61 * 1000));
  });

  test('a server witness that agrees with the wall confirms a long gap',
      () async {
    final hwm = _MemHwm(_utc(_t0));
    final f = _Fake()..wall = _t0 + 90 * _day;
    final c = f.clock(hwm, server: (offsetMs: 1500, seq: 1));
    await c.checkHighWaterMark();
    expect(hwm.value!.millisecondsSinceEpoch, _t0 + 90 * _day);
  });

  test('a server witness that disagrees caps the mark at server time',
      () async {
    final hwm = _MemHwm(_utc(_t0));
    final f = _Fake()..wall = _t0 + 365 * _day;
    // Server says it is really ~now: wall is a year fast.
    final c = f.clock(hwm, server: (offsetMs: -365 * _day, seq: 1));
    await c.checkHighWaterMark();
    expect(hwm.value!.millisecondsSinceEpoch,
        lessThanOrEqualTo(_t0 + 10 * 60 * 1000));
  });

  test('set-back is still detected and the mark is never lowered', () async {
    final f = _Fake();
    final hwm = _MemHwm(_utc(f.wall + _day));
    final c = f.clock(hwm);
    await c.checkHighWaterMark();
    expect(c.drainFlags().single['type'], 'clock_before_high_water_mark');
    expect(hwm.value!.millisecondsSinceEpoch, f.wall + _day);
    expect((await c.trustedNowUtc()).millisecondsSinceEpoch, f.wall + _day);
  });
}
