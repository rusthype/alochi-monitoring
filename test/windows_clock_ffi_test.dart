// Windows-only reality checks (skipped everywhere else).
//
//  * the REAL kernel32 `GetTickCount64` behind MonitoredClock's default tick
//    source is monotonic, tracks wall time, and drives the skew detector;
//  * dart:io UDP behaves on Windows the way the LAN hub assumes.
//
// Lines prefixed `INFO-WINDOWS:` are collected into the CI job summary. They
// are observations (limited runner networking, ...), never assertions.
import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/local_server/lan_discovery.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

// ignore: avoid_print
void _info(String msg) => print('INFO-WINDOWS: $msg');

/// Independent lookup, so the test does not trust MonitoredClock's own
/// (silently falling back) binding.
int Function() _directGetTickCount64() => DynamicLibrary.open('kernel32.dll')
    .lookupFunction<Uint64 Function(), int Function()>('GetTickCount64');

void main() {
  final skip = Platform.isWindows ? false : 'Windows only (GetTickCount64/UDP)';

  group('GetTickCount64 via MonitoredClock', () {
    test('platformTicksMs really is GetTickCount64 (not the Stopwatch fallback)',
        () {
      final direct = _directGetTickCount64();
      final a = direct();
      final b = platformTicksMs();
      final c = direct();
      expect(b, inInclusiveRange(a, c + 50),
          reason: 'platformTicksMs=$b outside direct GetTickCount64 [$a,$c]');
      _info('uptime(GetTickCount64)=${(c / 60000).toStringAsFixed(1)} min');
    });

    test('is monotonic over many consecutive calls', () {
      var prev = platformTicksMs();
      for (var i = 0; i < 100000; i++) {
        final t = platformTicksMs();
        expect(t, greaterThanOrEqualTo(prev));
        prev = t;
      }
    });

    test('~1 s apart matches Stopwatch within 250 ms', () async {
      final sw = Stopwatch()..start();
      final t0 = platformTicksMs();
      await Future<void>.delayed(const Duration(seconds: 1));
      final dTicks = platformTicksMs() - t0;
      final dWatch = sw.elapsedMilliseconds;
      expect((dTicks - dWatch).abs(), lessThanOrEqualTo(250),
          reason: 'ticks=$dTicks stopwatch=$dWatch');
      expect(dTicks, greaterThan(700));
    });

    test('real tick source + fake wall clock: skew flags, trusted time holds',
        () {
      var wallOffset = 0;
      final clock = MonitoredClock(
        ticks: platformTicksMs, // the REAL Windows source
        wall: () => DateTime.now().millisecondsSinceEpoch + wallOffset,
        highWaterStore: _MemHwm(),
      );
      final trusted0 = clock.nowMs;

      clock.checkNow();
      expect(clock.pendingFlags, isEmpty, reason: 'no skew yet');

      wallOffset += const Duration(hours: 1).inMilliseconds; // +1 h
      clock.checkNow();
      wallOffset -= const Duration(minutes: 90).inMilliseconds; // -> -30 min
      clock.checkNow();

      final flags = clock.drainFlags();
      expect(flags.map((f) => f['type']), ['clock_forward', 'clock_backward']);
      expect((flags[0]['skew_ms'] as int),
          closeTo(const Duration(hours: 1).inMilliseconds, 2000));
      expect((flags[1]['skew_ms'] as int),
          closeTo(-const Duration(minutes: 90).inMilliseconds, 2000));

      // The trusted clock ignored both jumps: only real elapsed time passed.
      expect(clock.nowMs - trusted0, lessThan(2000));
      expect(clock.wallMs - DateTime.now().millisecondsSinceEpoch,
          closeTo(-const Duration(minutes: 30).inMilliseconds, 2000));
    });
  }, skip: skip);

  group('Windows UDP', () {
    final loop = InternetAddress.loopbackIPv4;

    test('loopback RawDatagramSocket with reuseAddress binds, sends, receives',
        () async {
      final rx = await RawDatagramSocket.bind(loop, 0, reuseAddress: true);
      addTearDown(rx.close);
      final tx = await RawDatagramSocket.bind(loop, 0);
      addTearDown(tx.close);
      final got = Completer<Datagram>();
      rx.listen((e) {
        if (e == RawSocketEvent.read && !got.isCompleted) {
          final d = rx.receive();
          if (d != null) got.complete(d);
        }
      });
      tx.send(Uint8List.fromList([1, 2, 3, 4]), loop, rx.port);
      final d = await got.future.timeout(const Duration(seconds: 5));
      expect(d.data, [1, 2, 3, 4]);
      expect(d.address.address, '127.0.0.1');
    });

    test('INFO: two reuseAddress binds on one port (hub + student on one PC)',
        () async {
      final a = await RawDatagramSocket.bind(loop, 0, reuseAddress: true);
      addTearDown(a.close);
      try {
        final b =
            await RawDatagramSocket.bind(loop, a.port, reuseAddress: true);
        b.close();
        _info('second reuseAddress bind on UDP ${a.port}: OK');
      } catch (e) {
        _info('second reuseAddress bind on UDP ${a.port}: FAILED (${e.runtimeType})');
      }
    });

    test('INFO: 255.255.255.255 broadcast send + any-interface receive',
        () async {
      // Informational: hosted runners may block broadcast entirely.
      RawDatagramSocket? rx;
      RawDatagramSocket? tx;
      try {
        rx = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0,
            reuseAddress: true);
        tx = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
        tx.broadcastEnabled = true;
        final got = Completer<bool>();
        final r = rx;
        r.listen((e) {
          if (e == RawSocketEvent.read && r.receive() != null) {
            if (!got.isCompleted) got.complete(true);
          }
        });
        var sent = 0;
        for (var i = 0; i < 5 && !got.isCompleted; i++) {
          sent = tx.send(Uint8List.fromList([9, 9]),
              InternetAddress('255.255.255.255'), r.port);
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
        final received = await got.future
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        _info('255.255.255.255 broadcast: send()=$sent bytes, '
            'received on same PC: $received');
      } catch (e) {
        _info('255.255.255.255 broadcast: ${e.runtimeType} (not a failure)');
      } finally {
        tx?.close();
        rx?.close();
      }
    });

    test('INFO: broadcast routes the hub would announce on', () async {
      try {
        final routes = await defaultBroadcastRoutes();
        _info('broadcast routes: '
            '${routes.map((r) => "${r.local.address}->${r.targets.map((t) => t.address).join("|")}").join("; ")}'
            '${routes.isEmpty ? "(none)" : ""}');
      } catch (e) {
        _info('broadcast routes: ${e.runtimeType} (not a failure)');
      }
    });
  }, skip: skip);
}
