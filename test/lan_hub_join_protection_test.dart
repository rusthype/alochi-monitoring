// /join abuse limits that had no HTTP-level test: the per-address request
// bucket, the failed-join counter reset on success, per-address isolation of a
// lockout, and the per-address cap on slow (half-sent) join bodies.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/local_server/hub_guard.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/lan_test_pack.dart';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late int ticks;
  late ShelfHub hub;
  late http.Client client;

  setUpAll(() {
    HttpOverrides.global = null; // real loopback sockets
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    client = http.Client();
    tmp = Directory.systemTemp.createTempSync('lan_join_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    ticks = 1000000;
    final clock = MonitoredClock(
        ticks: () => ticks, wall: () => 0, highWaterStore: _MemHwm());
    final session = await OfflinePackSession.open(
        lanTestPack(), makeMediaDir(tmp, 'a' * 64));
    hub = ShelfHub(session,
        bindAddress: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
        clock: clock);
    await hub.start(announce: false);
  });

  tearDown(() async {
    client.close();
    await hub.stop();
    hub.dispose();
    OfflinePackSession.close();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Uri url(String path) => Uri.parse('http://127.0.0.1:${hub.port}$path');

  Future<http.Response> join(String code, [String machine = 'm']) =>
      client.post(url('/join'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'code': code, 'machine_id': machine}));

  String wrongCode() => hub.state!.code == '000000' ? '111111' : '000000';

  test(
      'a /join flood from one address hits the request bucket (429), then '
      'recovers on the monotonic clock', () async {
    var limited = 0;
    for (var i = 0; i < 40; i++) {
      // Malformed body: 400 and NOT a wrong-code failure, so only the bucket
      // can produce the 429s.
      final r = await client.post(url('/join'),
          headers: {'content-type': 'application/json'}, body: '[]');
      if (r.statusCode == 429) {
        limited++;
        expect(jsonDecode(r.body), {'error': 'rate_limited'});
        expect(r.headers['retry-after'], '2');
      } else {
        expect(r.statusCode, 400);
      }
    }
    expect(limited, greaterThan(0));
    ticks += 40000; // refill
    expect((await join(hub.state!.code)).statusCode, 200);
  });

  test('a successful join resets the wrong-code counter of that address',
      () async {
    for (var i = 0; i < 4; i++) {
      expect((await join(wrongCode())).statusCode, 401);
    }
    expect((await join(hub.state!.code)).statusCode, 200);
    // 4 more misses: would have been blocked at the 5th overall without reset.
    for (var i = 0; i < 4; i++) {
      expect((await join(wrongCode())).statusCode, 401);
    }
    // ...and the 5th since the success blocks.
    expect((await join(wrongCode())).statusCode, 401);
    final blocked = await join(hub.state!.code);
    expect(blocked.statusCode, 429);
    expect(int.parse(blocked.headers['retry-after']!), greaterThan(0));
  });

  test('one address being locked out does not lock out another', () {
    var t = 0;
    final gate = JoinFailureGate(ticks: () => t);
    for (var i = 0; i < 5; i++) {
      gate.recordFailure('10.0.0.1');
    }
    expect(gate.blockedForMs('10.0.0.1'), isNotNull);
    expect(gate.blockedForMs('10.0.0.2'), isNull);
    t += 61000;
    expect(gate.blockedForMs('10.0.0.1'), isNull);
  });

  test(
      'half-sent join bodies hold at most maxConcurrentJoinPerIp slots; the '
      'next join is 503 busy, and the slots free up at the body deadline',
      () async {
    final socks = <Socket>[];
    for (var i = 0; i < HubLimits.maxConcurrentJoinPerIp; i++) {
      final s = await Socket.connect('127.0.0.1', hub.port!);
      s.write('POST /join HTTP/1.1\r\nHost: x\r\n'
          'Content-Type: application/json\r\nContent-Length: 100\r\n\r\n{');
      await s.flush();
      socks.add(s);
    }
    // Let the hub register all of them as in-flight joins.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    final busy = await join(hub.state!.code);
    expect(busy.statusCode, 503);
    expect(jsonDecode(busy.body), {'error': 'busy'});

    // Slow-body deadline (3 s) frees the slots.
    await Future<void>.delayed(
        HubLimits.smallBodyTimeout + const Duration(milliseconds: 700));
    for (final s in socks) {
      s.destroy();
    }
    ticks += 40000; // bucket refill (monotonic)
    expect((await join(hub.state!.code)).statusCode, 200);
  });
}
