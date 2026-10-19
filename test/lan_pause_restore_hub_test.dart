// A student who leaves a paused LAN test and re-enters must get the SAME
// attempt back (pause + extra time kept), the hub must not show a ghost
// paused row while the PC is out of the test, and the "time left" column
// must follow what the student's own countdown reports.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/offline_crypto.dart';
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
  late String base;
  late http.Client client;

  setUpAll(() {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    client = http.Client();
    tmp = Directory.systemTemp.createTempSync('lan_pause_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    ticks = 1000000;
    final sha = OfflineCrypto.sha256Hex(lanMediaBytes);
    final media = makeMediaDir(tmp, sha);
    final session = await OfflinePackSession.open(
        lanTestPack(mediaRef: 'media/$sha.jpg'), media);
    hub = ShelfHub(session,
        bindAddress: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
        clock: MonitoredClock(
            ticks: () => ticks, wall: () => 0, highWaterStore: _MemHwm()));
    await hub.start(announce: false);
    base = 'http://127.0.0.1:${hub.port}';
  });

  tearDown(() async {
    client.close();
    await hub.stop();
    hub.dispose();
    OfflinePackSession.close();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<String> join() async {
    final r = await client.post(Uri.parse('$base/join'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'code': hub.state!.code,
          'machine_id': 'm1',
          'device_name': 'PC m1'
        }));
    return (jsonDecode(r.body) as Map)['token'] as String;
  }

  Future<Map<String, dynamic>> ping(
      String token, Map<String, dynamic> b) async {
    final r = await client.post(Uri.parse('$base/ping'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $token'
        },
        body: jsonEncode(b));
    expect(r.statusCode, 200, reason: r.body);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Map<String, dynamic> inTest(String session, {int? remaining}) => {
        'session_id': session,
        'name': 'Valiyev Ali',
        'test_key': 't_all',
        'status': 'active',
        'student_code': lanS1,
        if (remaining != null) 'remaining_seconds': remaining,
        'capabilities': ['pause_lock', 'seat_id'],
      };

  Map<String, dynamic> idle() => {
        'session_id': 'device-1',
        'name': 'Valiyev Ali',
        'test_key': '',
        'status': 'active',
        'capabilities': ['pause_lock', 'seat_id'],
      };

  test(
      'left while paused: no ghost row, and the SAME attempt re-claims with '
      'pause and extra time intact', () async {
    final t = await join();
    await ping(t, inTest('attempt-1'));
    final id = hub.state!.views().single.id;
    hub.state!.setLocked(id, true);
    hub.state!.addExtraTime(id, 300);
    expect((await ping(t, inTest('attempt-1')))['locked'], true);

    // The student's PC leaves the test (device-level idle ping).
    await ping(t, idle());
    final gone = hub.state!.views().single;
    expect(gone.inTest, isFalse);
    expect(gone.locked, isFalse, reason: 'no ghost paused row');

    // Re-entering: same attempt id.
    final back = await ping(t, inTest('attempt-1'));
    expect(back['conflict'], false);
    expect(back['locked'], true, reason: 'pause must be honoured on resume');
    expect(back['extra_time_seconds'], 300);
    final v = hub.state!.views().single;
    expect(v.inTest, isTrue);
    expect(v.locked, isTrue);
  });

  test('a genuinely new attempt id starts clean (pause is not inherited)',
      () async {
    final t = await join();
    await ping(t, inTest('attempt-1'));
    hub.state!.setLocked(hub.state!.views().single.id, true);
    await ping(t, idle());
    final fresh = await ping(t, inTest('attempt-2'));
    expect(fresh['locked'], false);
    expect(fresh['extra_time_seconds'], 0);
  });

  test('hub "time left" follows the remaining seconds the client reports',
      () async {
    final t = await join();
    await ping(t, inTest('attempt-1', remaining: 5855)); // 97:35
    final id = hub.state!.views().single.id;
    expect(hub.state!.views().single.remainingSeconds, 5855);
    // Pack says 30 min; the client's own countdown wins. While paused it
    // does not drain.
    hub.state!.setLocked(id, true);
    await ping(t, inTest('attempt-1', remaining: 5855));
    ticks += 600000;
    expect(hub.state!.views().single.remainingSeconds, 5855);
  });

  Map<String, dynamic> finished(String session) =>
      {...inTest(session), 'status': 'finished'};

  test(
      "a 'finished' ping that keeps the test key abandons the attempt; the "
      'same attempt re-claims pause and extra time', () async {
    final t = await join();
    await ping(t, inTest('attempt-1'));
    final id = hub.state!.views().single.id;
    hub.state!.setLocked(id, true);
    hub.state!.addExtraTime(id, 120);

    await ping(t, finished('attempt-1'));
    final gone = hub.state!.views().single;
    expect(gone.inTest, isFalse);
    expect(gone.locked, isFalse);

    final back = await ping(t, inTest('attempt-1'));
    expect(back['conflict'], false);
    expect(back['locked'], true);
    expect(back['extra_time_seconds'], 120);
  });

  test("a 'finished' ping AFTER a stored result does not resurrect it",
      () async {
    final t = await join();
    await ping(t, inTest('attempt-1'));
    final r = await client.post(Uri.parse('$base/result'),
        headers: {
          'content-type': 'application/json',
          'authorization': 'Bearer $t',
          'idempotency-key': 'k-1'
        },
        body: jsonEncode({'payload': lanResultPayload()}));
    expect(r.statusCode, 200, reason: r.body);
    expect(hub.state!.views().single.inTest, isFalse);

    await ping(t, finished('attempt-1'));
    expect(hub.state!.views().single.inTest, isFalse);
    // The attempt is over for good: re-claiming it is refused (ended).
    final late = await ping(t, inTest('attempt-1'));
    expect(late['conflict'], false);
    expect(hub.state!.views().single.inTest, isFalse);
  });
}
