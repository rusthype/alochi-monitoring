// The hub's own clock-tamper flags ride along with an accepted LAN result and
// are consumed only once that row is stored: a failed append keeps them for
// the next accepted result, an idempotent replay neither consumes nor
// re-attaches them. (Pack-session twin: result_drain_transactional_test.dart.)
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
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

final String _mediaSha = OfflineCrypto.sha256Hex(lanMediaBytes);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late int ticks;
  late int wall;
  late MonitoredClock clock;
  late ShelfHub hub;
  late String base;
  late http.Client client;

  setUpAll(() {
    HttpOverrides.global = null; // real loopback sockets
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    client = http.Client();
    tmp = Directory.systemTemp.createTempSync('hub_flags_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    ticks = 1000000;
    wall = DateTime.utc(2026, 10, 17, 9).millisecondsSinceEpoch;
    clock = MonitoredClock(
        ticks: () => ticks, wall: () => wall, highWaterStore: _MemHwm());
    final media = makeMediaDir(tmp, _mediaSha);
    final session = await OfflinePackSession.open(
        lanTestPack(mediaRef: 'media/$_mediaSha.jpg'), media);
    hub = ShelfHub(session,
        bindAddress: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
        hubName: 'test-hub',
        clock: clock);
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

  /// The hub PC's date is set forward by an hour: one `clock_forward` flag.
  void tamper() {
    ticks += 5000;
    wall += 5000 + 3600000;
    clock.checkNow();
  }

  Future<http.Response> post(String path, Object body,
          {String? token, Map<String, String> headers = const {}}) =>
      client.post(Uri.parse('$base$path'),
          headers: {
            'content-type': 'application/json',
            if (token != null) 'authorization': 'Bearer $token',
            ...headers,
          },
          body: jsonEncode(body));

  Future<String> join() async {
    final r = await post('/join', {
      'code': hub.state!.code,
      'machine_id': 'm1',
      'device_name': 'PC m1',
    });
    expect(r.statusCode, 200, reason: r.body);
    return (jsonDecode(r.body) as Map)['token'] as String;
  }

  Future<http.Response> sendResult(String t, String key) => post('/result',
      {'payload': lanResultPayload(), 'incidents': [], 'clock_flags': []},
      token: t, headers: {'idempotency-key': key});

  List<String> flagTypes(PackResultRow r) => [
        for (final f in (jsonDecode(r.metaJson) as Map)['clock_flags'] as List)
          (f as Map)['type'] as String
      ];

  /// Makes every pack_results INSERT fail while the table stays readable (the
  /// idempotency lookup and chain-usage reads before the append still work).
  Future<void> breakAppend() async => (await OfflineQueue.db)
      .execute("CREATE TRIGGER fail_append BEFORE INSERT ON pack_results "
          "BEGIN SELECT RAISE(ABORT, 'disk full'); END");
  Future<void> fixAppend() async =>
      (await OfflineQueue.db).execute('DROP TRIGGER fail_append');

  test(
      'a failed append keeps the hub flags; the next accepted result '
      'carries them and consumes them', () async {
    final t = await join();
    tamper();
    expect(clock.pendingFlags, hasLength(1));

    await breakAppend();
    final failed = await sendResult(t, 'k1');
    expect(failed.statusCode, isNot(200));
    expect(await PackResultsDb.rowsForPack(lanPackUuid), isEmpty);
    expect(clock.pendingFlags, hasLength(1), reason: 'not consumed');

    await fixAppend();
    expect((await sendResult(t, 'k1')).statusCode, 200);
    final rows = await PackResultsDb.rowsForPack(lanPackUuid);
    expect(rows, hasLength(1));
    expect(flagTypes(rows.single), ['clock_forward']);
    expect(clock.pendingFlags, isEmpty, reason: 'consumed once stored');
  });

  test('success consumes the flags, so the next result does not repeat them',
      () async {
    final t = await join();
    tamper();
    expect((await sendResult(t, 'a')).statusCode, 200);
    expect((await sendResult(t, 'b')).statusCode, 200);
    final rows = await PackResultsDb.rowsForPack(lanPackUuid);
    expect(flagTypes(rows[0]), ['clock_forward']);
    expect(flagTypes(rows[1]), isEmpty);
  });

  test('an idempotent replay neither consumes nor re-attaches the flags',
      () async {
    final t = await join();
    tamper();
    expect((await sendResult(t, 'k1')).statusCode, 200);
    expect(clock.pendingFlags, isEmpty);

    tamper(); // a NEW flag arrives after k1 was stored
    expect(clock.pendingFlags, hasLength(1));
    expect((await sendResult(t, 'k1')).statusCode, 200); // replay
    var rows = await PackResultsDb.rowsForPack(lanPackUuid);
    expect(rows, hasLength(1));
    expect(flagTypes(rows.single), ['clock_forward'], reason: 'not doubled');
    expect(clock.pendingFlags, hasLength(1),
        reason: 'replay keeps the new one');

    // The next genuinely new result picks the waiting flag up, exactly once.
    expect((await sendResult(t, 'k2')).statusCode, 200);
    rows = await PackResultsDb.rowsForPack(lanPackUuid);
    expect(rows, hasLength(2));
    expect(flagTypes(rows[1]), ['clock_forward']);
    expect(clock.pendingFlags, isEmpty);
  });
}
