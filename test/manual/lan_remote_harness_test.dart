// Manual cross-machine harness for the offline LAN client against a REAL hub
// (e.g. the teacher app on another PC). Skipped unless env vars are set, so it
// costs CI nothing.
//
// It needs Flutter (the client pulls in plugins), hence `flutter test`, not
// plain `dart run`.
//
// RUN against a remote hub (read host / port / 6-digit code from the hub's
// "teacher LAN" screen; over Tailscale use the hub PC's 100.x.y.z address --
// UDP discovery does not cross it, so the address is typed):
//
//   LAN_HOST=100.125.36.49 LAN_PORT=<port> LAN_CODE=<6 digits> \
//     flutter test test/manual/lan_remote_harness_test.dart --no-pub -r expanded
//
// RUN against a local loopback hub (self-check of the harness itself, uses the
// golden pack fixture):
//
//   LAN_LOCAL=1 flutter test test/manual/lan_remote_harness_test.dart --no-pub -r expanded
//
// Each step prints `PASS|FAIL <step>`. Two synthetic results are written to
// the hub's pack (student = first roster student, test = first catalog test),
// so use a throwaway class/pack, not a live exam. Keys are unique per run
// (`harness-<ms>`), so reruns add two more results each.
//
// Step 6 (outbox) cannot point at a closed port (a join needs a live hub), so
// the session's http client is wrapped and made to throw SocketException while
// "down" -- the identical code path as a dead hub (kLanUnreachable).
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

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

/// Pass-through client that can pretend the network is gone.
class _FlakyClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  bool down = false;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    if (down) throw const SocketException('harness: simulated unreachable hub');
    return _inner.send(request);
  }

  @override
  void close() => _inner.close();
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

  test(
    'LAN client vs hub',
    () async {
      HttpOverrides.global = null; // real sockets
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final tmp = Directory.systemTemp.createTempSync('lan_harness_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));

      ShelfHub? hub;
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

      late String host;
      late int port;
      late String code;
      try {
        if (local) {
          final keys = OfflineKeys(
            signingPem: File(
              '$_fixtures/test_signing_public.pem',
            ).readAsStringSync(),
            resultsPem: File(
              '$_fixtures/test_results_public.pem',
            ).readAsStringSync(),
          );
          final pack = await PackLoader(keys: keys).open(
            File('$_fixtures/golden.alochipack').readAsBytesSync(),
            '12345678',
          );
          final session = await OfflinePackSession.open(
            pack,
            Directory(p.join(tmp.path, 'media')),
          );
          hub = ShelfHub(
            session,
            bindAddress: InternetAddress.loopbackIPv4,
            firstPort: 0,
            lastPort: 0,
            clock: MonitoredClock(
              ticks: () => 1000000,
              wall: () => 0,
              highWaterStore: _MemHwm(),
            ),
          );
          await hub.start(announce: false);
          host = '127.0.0.1';
          port = hub.port!;
          code = hub.state!.code;
        } else {
          host = env['LAN_HOST']!;
          port = int.parse(env['LAN_PORT']!);
          code = env['LAN_CODE']!;
        }
        // ignore: avoid_print
        print('hub: $host:$port (${local ? 'local loopback' : 'remote'})');

        final client = _FlakyClient();
        // 1. join
        final s = await step('1 join with host:port + class code', () {
          return LanClientSession.join(
            host: host,
            port: port,
            code: code,
            client: client,
            machineId: 'harness-${DateTime.now().millisecondsSinceEpoch}',
            deviceName: 'lan-harness',
            mediaDirFor: (id) async => Directory(p.join(tmp.path, 'cm')),
          );
        });
        if (s == null) return;
        final api = LanClientApi(s);

        // 2. roster / groups / tests
        final data =
            await step('2 fetch groups + students + catalog', () async {
          final groups = await api.fetchGroups('');
          if (groups.isEmpty) throw 'hub returned no groups';
          final gid = groups.first['id']?.toString() ?? '';
          final students = await api.fetchStudents(gid);
          if (students.isEmpty) throw 'group $gid has no students';
          final cat = await api.fetchTestCatalog(groupId: gid);
          if (cat.isEmpty) throw 'catalog empty';
          pass(
            '  counts',
            'groups=${groups.length} students=${students.length} tests=${cat.length}',
          );
          return (
            gid: gid,
            sid: students.first['id']?.toString() ?? '',
            tkey: cat.first['key']?.toString() ??
                cat.first['test_key']?.toString() ??
                '',
          );
        });
        if (data == null) return;
        if (data.sid.isEmpty || data.tkey.isEmpty) {
          fail(
            '2 ids',
            'empty student id or test key: ${data.sid} / ${data.tkey}',
          );
          return;
        }

        // 3. open a test's content
        await step('3 open test content ${data.tkey}', () async {
          final t = await api.fetchTest(data.tkey, groupId: data.gid);
          if (t == null || t.isEmpty) throw 'fetchTest returned null/empty';
          pass('  body', 'top-level keys: ${t.keys.take(6).join(',')}');
        });

        Map<String, dynamic> payload([String note = 'a']) => {
              'name': 'LAN Harness',
              'grade': 5,
              'variant': '1',
              'source': 'flutter',
              'student_id': data.sid,
              'group_id': data.gid,
              'school_code': s.schoolCode,
              'test_key': data.tkey,
              'raw_answers': {'harness': note},
              'detail': {'test_key': data.tkey},
            };

        // Raw replay: identical body must be acked again (200); a DIFFERENT body
        // under the same key must be refused (409) -- proof the key is stored.
        Future<int> replay(Map<String, dynamic> pl, String k) async {
          final r = await s.request(
            'POST',
            '/result',
            body: utf8.encode(
              jsonEncode({'payload': pl, 'incidents': [], 'clock_flags': []}),
            ),
            headers: {'content-type': 'application/json', 'idempotency-key': k},
          );
          return r.statusCode;
        }

        // recordResult() also fires its own background flush; flushOutbox() then
        // returns 0 while that one is running. So: retry until the outbox is empty.
        Future<void> drain() async {
          for (var i = 0; i < 100; i++) {
            await s.flushOutbox();
            if ((await LanOutboxDb.pending(s.packUuid)).isEmpty) return;
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
        }

        // 4. submit one result, delivered through the outbox
        final key = 'harness-${DateTime.now().millisecondsSinceEpoch}';
        await step('4 submit result key=$key (outbox -> hub ack)', () async {
          final r = await api.submitLocalResultFull(payload(), key);
          if (r['synced'] != true) throw 'enqueue failed: $r';
          await drain();
          final left = (await LanOutboxDb.pending(s.packUuid)).length;
          if (left != 0) {
            throw 'outbox still holds $left row(s); hold=${s.hold.value}';
          }
        });

        // 5. dedupe
        await step('5 same key again -> deduped', () async {
          final same = await replay(payload(), key);
          if (same != 200) throw 'identical replay expected 200, got $same';
          final diff = await replay(payload('different'), key);
          if (diff != 409) {
            throw 'different body, same key expected 409, got $diff';
          }
          if (hub != null) {
            if (hub.state!.resultsAccepted != 1) {
              throw 'hub accepted ${hub.state!.resultsAccepted}, expected 1';
            }
            final rows = await PackResultsDb.rowsForPack(s.packUuid);
            if (rows.length != 1) {
              throw 'hub pack has ${rows.length} rows, expected 1';
            }
          }
        });

        // 6. outbox while the hub is "unreachable", flush on reconnect
        final key2 = '$key-offline';
        await step(
          '6 outbox holds result while hub down, flushes on reconnect',
          () async {
            client.down = true;
            final r = await api.submitLocalResultFull(payload('offline'), key2);
            if (r['synced'] != true) throw 'enqueue failed: $r';
            final acked = await s.flushOutbox();
            await Future<void>.delayed(const Duration(milliseconds: 300));
            final held = (await LanOutboxDb.pending(s.packUuid)).length;
            if (acked != 0 || held != 1) {
              throw 'while down: acked=$acked held=$held (expected 0 / 1)';
            }
            client.down = false;
            await drain();
            final left = (await LanOutboxDb.pending(s.packUuid)).length;
            if (left != 0) {
              throw 'after reconnect: outbox still holds $left (hold=${s.hold.value})';
            }
            final diff = await replay(payload('x'), key2);
            if (diff != 409) {
              throw 'delivered result not found on hub (replay=$diff)';
            }
            if (hub != null && hub.state!.resultsAccepted != 2) {
              throw 'hub accepted ${hub.state!.resultsAccepted}, expected 2';
            }
          },
        );

        s.close();
      } finally {
        // ignore: avoid_print
        print(failed == 0 ? 'ALL STEPS PASS' : 'FAILED STEPS: $failed');
        if (hub != null) {
          await hub.stop();
          hub.dispose();
          OfflinePackSession.close();
        }
        await OfflineQueue.resetForTest();
        tmp.deleteSync(recursive: true);
      }
      expect(failed, 0);
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
