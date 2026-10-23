// Manual hub kill/restart test for the offline LAN client. Env-gated like
// lan_remote_harness_test.dart (skipped by default, no CI cost).
//
// REMOTE (real hub process you kill and restart yourself):
//
//   LAN_HOST=100.125.36.49 LAN_PORT=<port> LAN_CODE=<6 digits> \
//     flutter test test/manual/lan_remote_crash_test.dart --no-pub -r expanded
//
//   The test is driven by signal files; watch stdout:
//     PHASE_A_DONE  -> result X was acked. KILL the hub process now, then:
//                      touch /tmp/lan_crash_go1
//     PHASE_B_DONE  -> result Y (hub dead) is parked in the outbox, result Z
//                      (replay of X) too. RESTART the hub on the SAME pack,
//                      read its NEW port + class code, then:
//                      echo "<port> <code>" > /tmp/lan_crash_go2
//   Each signal wait times out after 10 min. Stale signal files are deleted
//   at start. The restarted hub must reopen the same pack (same results DB),
//   otherwise step 5 fails on purpose (X must survive the crash).
//
// LOCAL (proves the logic without Windows: the test itself stops the loopback
// hub and starts a new one on the same open pack/results DB):
//
//   LAN_LOCAL=1 flutter test test/manual/lan_remote_crash_test.dart --no-pub -r expanded
//
// Writes 3 synthetic results to the hub's pack (X, Y, and a replay Z of X that
// must NOT be stored twice), so use a throwaway pack.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/lan_outbox_db.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/lan_client_api.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _fixtures = 'test/fixtures/offline';
const _go1 = '/tmp/lan_crash_go1';
const _go2 = '/tmp/lan_crash_go2';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

Future<String> _waitFile(String path) async {
  final f = File(path);
  final end = DateTime.now().add(const Duration(minutes: 10));
  while (!f.existsSync()) {
    if (DateTime.now().isAfter(end)) throw 'timeout waiting for $path';
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }
  await Future<void>.delayed(const Duration(milliseconds: 200));
  return f.readAsStringSync();
}

void main() {
  final env = Platform.environment;
  final local = env['LAN_LOCAL'] == '1';
  final remote = env['LAN_HOST'] != null &&
      env['LAN_PORT'] != null &&
      env['LAN_CODE'] != null;
  final skip = (local || remote)
      ? null
      : 'set LAN_HOST+LAN_PORT+LAN_CODE (remote) or LAN_LOCAL=1 (loopback)';

  TestWidgetsFlutterBinding.ensureInitialized();

  test('LAN client survives a hub kill/restart', () async {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = Directory.systemTemp.createTempSync('lan_crash_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    for (final f in [_go1, _go2]) {
      if (File(f).existsSync()) File(f).deleteSync();
    }

    ShelfHub? hub;
    OfflinePackSession? packSession;
    var failed = 0;
    void pass(String s, [String d = '']) =>
        // ignore: avoid_print
        print('PASS $s${d.isEmpty ? '' : ' -- $d'}');
    void fail(String s, Object e) {
      failed++;
      // ignore: avoid_print
      print('FAIL $s -- $e');
    }

    Future<T?> step<T>(String name, Future<T> Function() f) async {
      try {
        final r = await f();
        pass(name);
        return r;
      } catch (e) {
        fail(name, e);
        return null;
      }
    }

    Future<ShelfHub> startHub() async {
      final h = ShelfHub(packSession!,
          bindAddress: InternetAddress.loopbackIPv4,
          firstPort: 0,
          lastPort: 0,
          clock: MonitoredClock(
              ticks: () => 1000000, wall: () => 0, highWaterStore: _MemHwm()));
      await h.start(announce: false);
      return h;
    }

    final tag = DateTime.now().millisecondsSinceEpoch;
    LanClientSession? s;
    try {
      late String host;
      late int port;
      late String code;
      if (local) {
        final keys = OfflineKeys(
          signingPem:
              File('$_fixtures/test_signing_public.pem').readAsStringSync(),
          resultsPem:
              File('$_fixtures/test_results_public.pem').readAsStringSync(),
        );
        final pack = await PackLoader(keys: keys).open(
            File('$_fixtures/golden.alochipack').readAsBytesSync(), '12345678');
        packSession = await OfflinePackSession.open(
            pack, Directory(p.join(tmp.path, 'media')));
        hub = await startHub();
        host = '127.0.0.1';
        port = hub.port!;
        code = hub.state!.code;
      } else {
        host = env['LAN_HOST']!;
        port = int.parse(env['LAN_PORT']!);
        code = env['LAN_CODE']!;
      }

      Future<LanClientSession> join(int prt, String cd) =>
          LanClientSession.join(
            host: host,
            port: prt,
            code: cd,
            client: http.Client(),
            machineId: 'crash-$tag',
            deviceName: 'lan-crash',
            mediaDirFor: (id) async => Directory(p.join(tmp.path, 'cm')),
          );

      // 1. join + submit X, acked
      final keyX = 'crashX-$tag', keyY = 'crashY-$tag';
      late Map<String, dynamic> Function(String) payload;
      Future<void> drain(LanClientSession ses, {int seconds = 20}) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (DateTime.now().isBefore(end)) {
          await ses.flushOutbox();
          if ((await LanOutboxDb.pending(ses.packUuid)).isEmpty) return;
          await Future<void>.delayed(const Duration(milliseconds: 200));
        }
      }

      final ok1 = await step('1 join + submit X, acked by hub', () async {
        s = await join(port, code);
        final api = LanClientApi(s!);
        final groups = await api.fetchGroups('');
        if (groups.isEmpty) throw 'no groups on hub';
        final gid = groups.first['id']?.toString() ?? '';
        final students = await api.fetchStudents(gid);
        if (students.isEmpty) throw 'no students in group';
        final cat = await api.fetchTestCatalog(groupId: gid);
        if (cat.isEmpty) throw 'empty catalog';
        final sid = students.first['id']?.toString() ?? '';
        final tkey =
            cat.first['key']?.toString() ?? cat.first['test_key']?.toString();
        if (sid.isEmpty || tkey == null || tkey.isEmpty) {
          throw 'empty student/test id';
        }
        payload = (note) => {
              'name': 'LAN Crash',
              'grade': 5,
              'variant': '1',
              'source': 'flutter',
              'student_id': sid,
              'group_id': gid,
              'school_code': s!.schoolCode,
              'test_key': tkey,
              'raw_answers': {'crash': note},
              'detail': {'test_key': tkey},
            };
        final r = await api.submitLocalResultFull(payload('X'), keyX);
        if (r['synced'] != true) throw 'enqueue X failed: $r';
        await drain(s!);
        final left = (await LanOutboxDb.pending(s!.packUuid)).length;
        if (left != 0) throw 'X not acked, outbox holds $left';
        return true;
      });
      if (ok1 != true) return;

      // 2. kill signal
      // ignore: avoid_print
      print('PHASE_A_DONE');
      if (local) {
        await hub!.stop(); // sockets closed, tokens dropped, no goodbye
        hub.dispose();
        hub = null;
        // ignore: avoid_print
        print('(local) hub stopped');
      } else {
        // ignore: avoid_print
        print('KILL the hub, then: touch $_go1');
        final w = await step('2 wait for $_go1', () => _waitFile(_go1));
        if (w == null) return;
      }

      // 3. submit Y and replay-Z while the hub is really dead
      await step('3 Y + replay-of-X parked in outbox, caller not blocked',
          () async {
        final api = LanClientApi(s!);
        final sw = Stopwatch()..start();
        final ry = await api
            .submitLocalResultFull(payload('Y'), keyY)
            .timeout(const Duration(seconds: 15));
        final rz = await api
            .submitLocalResultFull(payload('X'), keyX)
            .timeout(const Duration(seconds: 15));
        sw.stop();
        if (ry['synced'] != true || rz['synced'] != true) {
          throw 'enqueue refused: $ry / $rz';
        }
        // Let the background flush attempts fail against the dead hub.
        await Future<void>.delayed(const Duration(seconds: 2));
        final acked = await s!.flushOutbox();
        final rows = await LanOutboxDb.pending(s!.packUuid);
        if (acked != 0) throw 'acked=$acked while hub is dead';
        final keys = rows.map((r) => r.idempotencyKey).toSet();
        if (!keys.contains(keyY) || !keys.contains(keyX) || rows.length != 2) {
          throw 'outbox keys=$keys (expected Y and replay-X, 2 rows)';
        }
        pass('  parked',
            'pending=${rows.length} (Y + Z), enqueue took ${sw.elapsedMilliseconds}ms');
      });

      // 4. restart signal
      // ignore: avoid_print
      print('PHASE_B_DONE');
      late int port2;
      late String code2;
      if (local) {
        hub = await startHub();
        port2 = hub.port!;
        code2 = hub.state!.code;
        // ignore: avoid_print
        print('(local) hub restarted on port $port2');
      } else {
        // ignore: avoid_print
        print('RESTART the hub on the same pack, then: '
            'echo "<port> <code>" > $_go2');
        final txt = await _waitFile(_go2);
        final parts = txt.trim().split(RegExp(r'\s+'));
        if (parts.length != 2 || int.tryParse(parts[0]) == null) {
          fail('4 read $_go2', 'expected "<port> <code>", got "$txt"');
          return;
        }
        port2 = int.parse(parts[0]);
        code2 = parts[1];
      }

      // 5. rejoin, drain, prove X (once) and Y exist
      final ses2 = await step('5a re-join restarted hub with new code', () {
        s!.close();
        return join(port2, code2);
      });
      if (ses2 == null) return;
      s = ses2;
      await step('5b outbox drains within 60s', () async {
        await drain(ses2, seconds: 60);
        final left = (await LanOutboxDb.pending(ses2.packUuid)).length;
        if (left != 0) {
          throw 'outbox still holds $left (hold=${ses2.hold.value})';
        }
      });

      Future<int> replay(String k, String note) async {
        final r = await ses2.request('POST', '/result',
            body: utf8.encode(jsonEncode({
              'payload': payload(note),
              'incidents': [],
              'clock_flags': []
            })),
            headers: {
              'content-type': 'application/json',
              'idempotency-key': k
            });
        return r.statusCode;
      }

      await step('5c X survived the crash and was not stored twice', () async {
        final same = await replay(keyX, 'X');
        final diff = await replay(keyX, 'other');
        if (same != 200 || diff != 409) {
          throw 'replay X same=$same(want 200) different=$diff(want 409)';
        }
      });
      await step('5d Y delivered after restart', () async {
        final same = await replay(keyY, 'Y');
        final diff = await replay(keyY, 'other');
        if (same != 200 || diff != 409) {
          throw 'replay Y same=$same(want 200) different=$diff(want 409)';
        }
      });
      if (local) {
        await step('5e hub results DB holds exactly X and Y', () async {
          final rows = await PackResultsDb.rowsForPack(ses2.packUuid);
          if (rows.length != 2) throw '${rows.length} rows, expected 2';
        });
      }
      s!.close();
    } finally {
      // ignore: avoid_print
      print(failed == 0 ? 'ALL STEPS PASS' : 'FAILED STEPS: $failed');
      if (hub != null) {
        await hub.stop();
        hub.dispose();
      }
      if (local) OfflinePackSession.close();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    }
    expect(failed, 0);
  }, skip: skip, timeout: const Timeout(Duration(minutes: 30)));
}
