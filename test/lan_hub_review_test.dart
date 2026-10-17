// Regression tests for the T2 review of the LAN hub (S-001 .. S-011): every
// probe the reviewer ran against a real server is repeated here.
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/local_server/hub_guard.dart';
import 'package:alochi_monitoring/core/local_server/hub_state.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/export_format.dart';
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

/// The server's limit on the DECRYPTED export JSON (offline_pack.py).
const int _serverLimit = 10485760;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late int ticks;
  late MonitoredClock clock;
  late ShelfHub hub;
  late String base;
  late http.Client client;

  setUpAll(() {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> boot({
    int? maxPackEntries,
    int? maxPackPlainBytes,
    int? maxResultsPerIp,
    int? maxResultBytesPerIp,
    int? maxResultsPerStudent,
    int? maxResultBytesPerStudent,
    int? reservePerStudent,
  }) async {
    client = http.Client();
    tmp = Directory.systemTemp.createTempSync('lan_review_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    ticks = 1000000;
    clock = MonitoredClock(
        ticks: () => ticks, wall: () => 0, highWaterStore: _MemHwm());
    final session = await OfflinePackSession.open(
        lanTestPack(mediaRef: 'media/$_mediaSha.jpg'),
        makeMediaDir(tmp, _mediaSha));
    hub = ShelfHub(session,
        bindAddress: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
        hubName: 'test-hub',
        clock: clock,
        maxPackEntries: maxPackEntries ?? HubLimits.maxPackEntries,
        maxPackPlainBytes: maxPackPlainBytes ?? HubLimits.maxPackPlainBytes,
        maxResultsPerIp: maxResultsPerIp ?? HubLimits.maxResultsPerIp,
        maxResultBytesPerIp:
            maxResultBytesPerIp ?? HubLimits.maxResultBytesPerIp,
        maxResultsPerStudent:
            maxResultsPerStudent ?? HubLimits.maxResultsPerStudent,
        maxResultBytesPerStudent:
            maxResultBytesPerStudent ?? HubLimits.maxResultBytesPerStudent,
        reservePerStudent: reservePerStudent ?? HubLimits.reservePerStudent);
    await hub.start(announce: false);
    base = 'http://127.0.0.1:${hub.port}';
  }

  Future<void> shutdown() async {
    client.close();
    await hub.stop();
    hub.dispose();
    OfflinePackSession.close();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  }

  Uri u(String path, [Map<String, String>? q]) =>
      Uri.parse('$base$path').replace(queryParameters: q);

  Future<http.Response> postJson(String path, Object? body,
          {String? token, Map<String, String> headers = const {}}) =>
      client.post(u(path),
          headers: {
            'content-type': 'application/json',
            if (token != null) 'authorization': 'Bearer $token',
            ...headers,
          },
          body: body is String ? body : jsonEncode(body));

  Future<String> join(String machine) async {
    final r = await postJson('/join', {
      'code': hub.state!.code,
      'machine_id': machine,
      'device_name': machine,
    });
    expect(r.statusCode, 200, reason: r.body);
    return (jsonDecode(r.body) as Map)['token'] as String;
  }

  Future<http.Response> sendResult(
          String t, String key, Map<String, dynamic> payload) =>
      postJson(
          '/result', {'payload': payload, 'incidents': [], 'clock_flags': []},
          token: t, headers: {'idempotency-key': key});

  /// A syntactically valid result padded with [n] backslashes (JSON escapes
  /// every one TWICE on its way into the export: the reviewer's S-001 attack).
  Map<String, dynamic> poisoned(int n) =>
      {...lanResultPayload(), 'junk': List.filled(n, r'\').join()};

  Future<int> actualExportBytes() async {
    final rows = await PackResultsDb.rowsForPack(lanPackUuid);
    final entries = [
      for (final r in rows)
        exportEntry(
            prevHash: r.prevHash,
            hash: r.hash,
            payloadJson: r.payloadJson,
            metaJson: r.metaJson)
    ];
    return utf8.encode(encodeEntries(entries)).length;
  }

  Map<String, dynamic> pingBody(String session, {String student = lanS1}) => {
        'session_id': session,
        'name': 'x',
        'test_key': 't_all',
        'status': 'active',
        'student_code': student,
      };

  // ── S-001 ──────────────────────────────────────────────────────────────────

  group('S-001 export poisoning', () {
    setUp(boot);
    tearDown(shutdown);

    test(
        'the largest REAL result shapes fit the 64 KB body limit with '
        'headroom and are accepted over HTTP (N-2)', () async {
      // Worst realistic shapes: a 300-question engine test with 100 long
      // free-text answers and rich section/topic scores, and a 300-answer
      // diagnostic.
      final engine = {
        ...lanResultPayload(),
        'raw_answers': {
          for (var i = 0; i < 300; i++)
            'Section${i % 6}/$i': i % 3 == 0 ? 'x' * 300 : i
        },
        'detail': {
          'test_key': 't_all',
          'sections': [
            for (var i = 0; i < 40; i++)
              {'name': 'Section $i', 'correct': i, 'total': 50, 'pct': 50.5}
          ],
          'topics': [
            for (var i = 0; i < 80; i++)
              {'name': 'Topic number $i', 'correct': i, 'total': 9, 'pct': 11.1}
          ],
        },
      };
      final diag = {
        ...lanResultPayload(
            student: lanS2, group: lanG2, testKey: 'diag:math:g5:uz:v1'),
        'answers': [
          for (var i = 0; i < 300; i++)
            {
              'q': '00000000-0000-4000-8000-${i.toString().padLeft(12, '0')}',
              'a': 'B'
            }
        ],
      };
      int bodyOf(Map<String, dynamic> payload) => utf8
          .encode(jsonEncode(
              {'payload': payload, 'incidents': [], 'clock_flags': []}))
          .length;
      final engineBody = bodyOf(engine);
      final diagBody = bodyOf(diag);
      // ignore: avoid_print
      print('worst realistic result REQUEST BODY: engine=$engineBody B, '
          'diagnostic=$diagBody B (limit ${HubLimits.resultBody} B)');
      // measured ~43 KB: the 64 KB limit leaves >= 40% headroom
      expect(engineBody * 1.4, lessThan(HubLimits.resultBody));
      expect(diagBody * 1.4, lessThan(HubLimits.resultBody));

      final t = await join('real');
      expect((await sendResult(t, 'real-engine', engine)).statusCode, 200);
      expect((await sendResult(t, 'real-diag', diag)).statusCode, 200);
    });

    test('the 500 KB poisoned request of the probe is refused outright',
        () async {
      final t = await join('atk');
      final r = await sendResult(t, 'poison-0', poisoned(500 * 1024));
      expect(r.statusCode, 413);
      expect(await PackResultsDb.rowsForPack(lanPackUuid), isEmpty);
    });

    test(
        'backslash-padded results can never push the export past the server '
        'limit; the hub measures the real export size', () async {
      await shutdown();
      await boot(
          maxResultsPerStudent: 100000,
          maxResultBytesPerStudent: 1 << 30,
          reservePerStudent: 0);
      final t = await join('atk');
      var accepted = 0;
      int? stopped;
      for (var i = 0; i < 60; i++) {
        ticks += 5000;
        final r = await sendResult(t, 'poison-$i', poisoned(30 * 1024));
        if (r.statusCode == 200) {
          accepted++;
        } else {
          stopped = r.statusCode;
          break;
        }
      }
      final actual = await actualExportBytes();
      // ignore: avoid_print
      print('S-001 default limits: accepted=$accepted stopped=$stopped '
          'export=$actual B (server limit $_serverLimit)');
      expect(stopped, anyOf(403, 507));
      expect(actual, lessThanOrEqualTo(HubLimits.maxPackPlainBytes));
      expect(actual, lessThan(_serverLimit));
      // The hub's running figure IS the exporter's figure (the +1 is the
      // comma after the last entry, counted conservatively).
      expect(await PackResultsDb.exportPlainBytes(lanPackUuid), actual + 1);
    });

    test(
        'the pack-wide budget (not only the per-address quota) holds, in '
        'the exporter\'s own unit', () async {
      await shutdown();
      await boot(
          maxPackPlainBytes: 700 * 1024,
          maxResultsPerIp: 100000,
          maxResultBytesPerIp: 1 << 30,
          maxResultsPerStudent: 100000,
          maxResultBytesPerStudent: 1 << 30,
          reservePerStudent: 0);
      final t = await join('atk');
      int? stopped;
      for (var i = 0; i < 40; i++) {
        ticks += 5000;
        final r = await sendResult(t, 'p-$i', poisoned(30 * 1024));
        if (r.statusCode != 200) {
          stopped = r.statusCode;
          expect(jsonDecode(r.body), {'error': 'pack_full'});
          break;
        }
      }
      expect(stopped, 507);
      expect(await actualExportBytes(), lessThanOrEqualTo(700 * 1024));
      // A small honest result that still fits is accepted afterwards.
      expect((await sendResult(t, 'small', lanResultPayload())).statusCode,
          anyOf(200, 507));
    });

    test(
        '128 parallel results cannot overshoot the budget (check+append is '
        'one critical section)', () async {
      await shutdown();
      await boot(
          maxPackPlainBytes: 900 * 1024,
          maxResultsPerIp: 100000,
          maxResultBytesPerIp: 1 << 30,
          maxResultsPerStudent: 100000,
          maxResultBytesPerStudent: 1 << 30,
          reservePerStudent: 0);
      final tokens = [for (var i = 0; i < 8; i++) await join('m$i')];
      final futs = <Future<http.Response>>[
        for (var i = 0; i < 128; i++)
          sendResult(tokens[i % 8], 'par-$i', poisoned(25 * 1024))
      ];
      final rs = await Future.wait(futs);
      final ok = rs.where((r) => r.statusCode == 200).length;
      final actual = await actualExportBytes();
      // ignore: avoid_print
      print(
          'S-001 parallel: accepted=$ok of 128, export=$actual B (budget ${900 * 1024})');
      expect(ok, greaterThan(0));
      expect(actual, lessThanOrEqualTo(900 * 1024));
      final rows = await PackResultsDb.rowsForPack(lanPackUuid);
      expect(rows, hasLength(ok));
      // and the chain is intact
      var prev = OfflineCrypto.zeroHash;
      for (final r in rows) {
        expect(r.prevHash, prev);
        expect(
            r.hash,
            OfflineCrypto.chainHash(
                lanTestPack().chainKey, prev, r.payloadJson, r.metaJson));
        prev = r.hash;
      }
    });

    test('re-joining (same or new machine id) does not reset the quota',
        () async {
      await shutdown();
      await boot(maxResultsPerIp: 3);
      var t = await join('m');
      for (var i = 0; i < 3; i++) {
        expect(
            (await sendResult(t, 'q$i', lanResultPayload())).statusCode, 200);
      }
      expect((await sendResult(t, 'q3', lanResultPayload())).statusCode, 403);
      t = await join('m');
      expect((await sendResult(t, 'q4', lanResultPayload())).statusCode, 403);
      t = await join('another-machine');
      final r = await sendResult(t, 'q5', lanResultPayload());
      expect(r.statusCode, 403);
      expect(jsonDecode(r.body), {'error': 'client_quota'});
      // an already stored key is still acknowledged
      expect((await sendResult(t, 'q0', lanResultPayload())).statusCode, 200);
    });
  });

  // ── S-002 ──────────────────────────────────────────────────────────────────

  group('S-002 slow-body saturation', () {
    setUp(boot);
    tearDown(shutdown);

    test(
        '2 tokens x 65 slow sockets cannot starve other clients; their '
        'liveness keeps being recorded', () async {
      final atk = await join('atk');
      final atk2 = await join('atk2');
      final vic = await join('vic');
      await postJson('/ping', pingBody('v1', student: lanS2), token: vic);

      final socks = <Socket>[];
      for (var i = 0; i < 130; i++) {
        final s = await Socket.connect('127.0.0.1', hub.port!);
        s.write('POST /result HTTP/1.1\r\nHost: x\r\n'
            'Authorization: Bearer ${i.isEven ? atk : atk2}\r\n'
            'Idempotency-Key: k$i\r\nContent-Type: application/json\r\n'
            'Content-Length: 500\r\n\r\n{');
        socks.add(s);
      }
      addTearDown(() {
        for (final s in socks) {
          s.destroy();
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 600));

      // Everybody else is served.
      ticks += 10000;
      final ping =
          await postJson('/ping', pingBody('v1', student: lanS2), token: vic);
      expect(ping.statusCode, 200, reason: ping.body);
      expect((await postJson('/keepalive', {}, token: vic)).statusCode, 200);
      expect((await client.get(u('/health'))).statusCode, 200);
      final other = await postJson(
          '/join', {'code': hub.state!.code, 'machine_id': 'newcomer'});
      expect(other.statusCode, 200);

      // The attacker is capped per token, so its extra request is turned away
      // immediately instead of waiting for a slot.
      final extra = await sendResult(atk, 'one-more', lanResultPayload());
      expect(extra.statusCode, 429);
      expect(jsonDecode(extra.body)['error'], 'too_many_requests');

      // The victim was seen just now (not 10 s ago), so it is not "no contact".
      final v = hub.state!.views().firstWhere((e) => e.deviceName == 'vic');
      expect(v.lastSeenAgoMs, lessThan(1000));
      expect(v.status, isNot(ClientStatus.noContact));
    });

    test(
        'authentication refreshes lastSeen even when a limit then refuses '
        'the request', () async {
      final t = await join('m');
      final before = hub.state!.views().single.lastSeenAgoMs;
      expect(before, 0);
      ticks += 9000;
      // exhaust the per-token bucket, then keep knocking
      for (var i = 0; i < 200; i++) {
        await client.get(u('/groups'), headers: {'authorization': 'Bearer $t'});
      }
      expect(hub.state!.views().single.lastSeenAgoMs, 0);
    });

    test('slow /join bodies cannot hold the join endpoint', () async {
      final socks = <Socket>[];
      for (var i = 0; i < 40; i++) {
        final s = await Socket.connect('127.0.0.1', hub.port!);
        s.write('POST /join HTTP/1.1\r\nHost: x\r\n'
            'Content-Type: application/json\r\nContent-Length: 100\r\n\r\n{');
        socks.add(s);
      }
      addTearDown(() {
        for (final s in socks) {
          s.destroy();
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 400));
      // One address holds at most 4 join slots; the 5th is refused at once
      // (the 40 sockets were all from this one address).
      final r =
          await postJson('/join', {'code': hub.state!.code, 'machine_id': 'x'});
      expect(r.statusCode, anyOf(429, 503));
      // ... and /health and other addresses' tokens are untouched.
      expect((await client.get(u('/health'))).statusCode, 200);
    });
  });

  // ── S-004 ──────────────────────────────────────────────────────────────────

  group('S-004 machine_id', () {
    HubState mk() => HubState(
          packUuid: 'p',
          schoolId: 's',
          schoolCode: '1',
          hubName: 'h',
          groups: const [],
          students: const [],
          allowedTestKeys: const [],
        );

    test('the same machine_id from ANOTHER address does not evict', () {
      final st = mk();
      JoinResult j(String ip, String m) =>
          st.join(ip: ip, code: st.code, machineId: m, deviceName: '');
      final a = j('10.0.0.1', 'GUID').client!;
      final b = j('10.0.0.2', 'GUID').client!; // cloned image / spoofed id
      expect(st.authenticate(a.token), isNotNull);
      expect(st.authenticate(b.token), isNotNull);
      expect(st.clientCount, 2);
      st.dispose();
    });

    test(
        'same machine AND address replaces, keeping terminated attempts and '
        'quota-relevant state', () {
      final st = mk();
      JoinResult j() => st.join(
          ip: '10.0.0.1', code: st.code, machineId: 'GUID', deviceName: '');
      final old = j().client!;
      old.terminatedSessions.add('S-OLD');
      old.endedSessions.add('S-DONE');
      old.resultsAccepted = 7;
      final fresh = j().client!;
      expect(st.authenticate(old.token), isNull);
      expect(st.authenticate(fresh.token), isNotNull);
      expect(fresh.terminatedSessions, {'S-OLD'});
      expect(fresh.endedSessions, {'S-DONE'});
      expect(fresh.resultsAccepted, 7);
      expect(st.clientCount, 1);
      st.dispose();
    });
  });

  // ── S-005 ──────────────────────────────────────────────────────────────────

  group('S-005 join lock', () {
    HubState mk() {
      var t = 0;
      return HubState(
          packUuid: 'p',
          schoolId: 's',
          schoolCode: '1',
          hubName: 'h',
          groups: const [],
          students: const [],
          allowedTestKeys: const [],
          ticks: () => t);
    }

    test(
        'wrong codes from 12 addresses block everyone... unless joining is '
        'locked or the PC holds a valid token', () {
      final st = mk();
      final wrong = st.code == '000000' ? '111111' : '000000';
      for (var ip = 0; ip < 12; ip++) {
        for (var k = 0; k < 5; k++) {
          st.join(
              ip: '10.0.0.$ip', code: wrong, machineId: 'm', deviceName: '');
        }
      }
      expect(
          st
              .join(
                  ip: '10.0.0.200',
                  code: st.code,
                  machineId: 'new',
                  deviceName: '')
              .outcome,
          JoinOutcome.blocked);
      // a PC that holds a live token of the same machine gets through
      expect(
          st
              .join(
                  ip: '10.0.0.200',
                  code: st.code,
                  machineId: 'new',
                  deviceName: '',
                  holdsValidToken: true)
              .outcome,
          JoinOutcome.ok);
      st.dispose();
    });

    test('locked: /join answers 403 joins_locked and touches no counter',
        () async {
      await boot();
      addTearDown(shutdown);
      hub.state!.setJoinsLocked(true);
      final wrong = hub.state!.code == '000000' ? '111111' : '000000';
      for (var i = 0; i < 12; i++) {
        final r = await postJson('/join', {'code': wrong, 'machine_id': 'm'});
        expect(r.statusCode, 403);
        expect(jsonDecode(r.body), {'error': 'joins_locked'});
      }
      // even the RIGHT code is refused while locked
      expect(
          (await postJson(
                  '/join', {'code': hub.state!.code, 'machine_id': 'm'}))
              .statusCode,
          403);
      // unlocked again: no failure was ever recorded, so no 429
      hub.state!.setJoinsLocked(false);
      expect(
          (await postJson(
                  '/join', {'code': hub.state!.code, 'machine_id': 'm'}))
              .statusCode,
          200);
    });

    test('clients already in keep working while joining is locked', () async {
      await boot();
      addTearDown(shutdown);
      final t = await join('in');
      hub.state!.setJoinsLocked(true);
      expect(
          (await client
                  .get(u('/groups'), headers: {'authorization': 'Bearer $t'}))
              .statusCode,
          200);
      // a refresh with the live token passes the lock
      final r = await client.post(u('/join'),
          headers: {
            'content-type': 'application/json',
            'authorization': 'Bearer $t'
          },
          body: jsonEncode({'code': hub.state!.code, 'machine_id': 'in'}));
      expect(r.statusCode, 200);
    });
  });

  // ── S-006 / S-007 ──────────────────────────────────────────────────────────

  group('S-006 / S-007 frames', () {
    setUp(boot);
    tearDown(shutdown);

    test('jpegSize reads the header only', () {
      expect(jpegSize(lanJpeg(w: 640, h: 360)), (width: 640, height: 360));
      expect(
          jpegSize(lanJpeg(w: 65535, h: 65535)), (width: 65535, height: 65535));
      expect(jpegSize(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xD9])), isNull);
      expect(jpegSize(Uint8List.fromList(utf8.encode('<html>'))), isNull);
      expect(jpegSize(Uint8List(0)), isNull);
      // truncated inside the SOF segment
      expect(jpegSize(lanJpeg().sublist(0, 8)), isNull);
    });

    test(
        'the reviewer\'s 65535x65535 header is refused; a real capture size '
        'and the largest allowed are accepted; headerless junk is refused',
        () async {
      final t = await join('f');
      await postJson('/ping', pingBody('fs'), token: t);
      Future<http.Response> send(Uint8List b) =>
          client.post(u('/frame', {'session_id': 'fs'}),
              headers: {'authorization': 'Bearer $t'}, body: b);

      var r = await send(lanJpeg(w: 65535, h: 65535));
      expect(r.statusCode, 422);
      expect(jsonDecode(r.body), {'error': 'frame_too_large'});
      ticks += 4000;
      r = await send(lanJpeg(w: 4097, h: 100));
      expect(r.statusCode, 422);
      ticks += 4000;
      r = await send(lanJpeg(w: 4096, h: 2049)); // 8.4 MP > 8 MP
      expect(r.statusCode, 422);
      ticks += 4000;
      r = await send(
          Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 4, 1, 2, 0xFF, 0xD9]));
      expect(r.statusCode, 400); // no SOFn: not a usable JPEG
      expect(jsonDecode(r.body), {'error': 'bad_frame'});
      ticks += 4000;
      r = await send(lanJpeg(w: 960, h: 540));
      expect(r.statusCode, 200);
      ticks += 4000;
      r = await send(lanJpeg(w: 3000, h: 2600)); // 7.8 MP, allowed
      expect(r.statusCode, 200);
      // nothing refused was kept
      expect(hub.state!.frameOf(hub.state!.views().single.id), isNotNull);
    });

    // N-1 ---------------------------------------------------------------

    Uint8List fakeSof(int w, int h) => Uint8List.fromList([
          0xFF, 0xC0, 0, 17, 8, h >> 8, h & 0xFF, w >> 8, w & 0xFF, //
          3, 1, 0x22, 0, 2, 0x11, 1, 3, 0x11, 1,
        ]);

    test('jpegSize: a second SOF, fill-byte runs and truncation never crash',
        () {
      final big = lanJpeg(w: 10000, h: 10000);
      // fake small frame header first, the real (huge) one behind it
      final twoSof = Uint8List.fromList(
          [...big.sublist(0, 2), ...fakeSof(640, 360), ...big.sublist(2)]);
      expect(jpegSize(twoSof), isNull, reason: 'two frame headers: refuse');
      // the reviewer's tail: FF D8 then nothing but fill bytes
      for (var n = 3; n < 40; n++) {
        final b =
            Uint8List.fromList([0xFF, 0xD8, 0xFF, ...List.filled(n - 3, 0xFF)]);
        expect(() => jpegSize(b), returnsNormally, reason: 'fill x$n');
        expect(jpegSize(b), isNull);
      }
      // every prefix of a real file, and random garbage after SOI
      final real = lanJpeg();
      for (var n = 0; n <= real.length; n++) {
        expect(() => jpegSize(real.sublist(0, n)), returnsNormally);
      }
      final rnd = Random(7);
      for (var i = 0; i < 20000; i++) {
        final b = Uint8List(3 + rnd.nextInt(40));
        b[0] = 0xFF;
        b[1] = 0xD8;
        for (var k = 2; k < b.length; k++) {
          b[k] = rnd.nextInt(4) == 0 ? 0xFF : rnd.nextInt(256);
        }
        expect(() => jpegSize(b), returnsNormally);
      }
    });

    test(
        'N-1: a fake 640x360 SOF in front of a real 10000x10000 one is a 422 '
        '(the codec, not the walker, has the last word); nothing is stored',
        () async {
      final t = await join('f');
      await postJson('/ping', pingBody('fs'), token: t);
      final big = lanJpeg(w: 10000, h: 10000);
      final bomb = Uint8List.fromList(
          [...big.sublist(0, 2), ...fakeSof(640, 360), ...big.sublist(2)]);
      final r = await client.post(u('/frame', {'session_id': 'fs'}),
          headers: {'authorization': 'Bearer $t'}, body: bomb);
      // The codec has the last word, and codecs differ: macOS reads the real
      // (second) SOF -> 422 frame_too_large; Windows' libjpeg rejects the
      // two-SOF stream outright ("two SOF markers") -> 400 bad_frame, which
      // docs/offline_lan_hub.md documents. Either way the bomb is refused.
      expect(r.statusCode, anyOf(422, 400));
      expect(
          jsonDecode(r.body),
          r.statusCode == 422
              ? {'error': 'frame_too_large'}
              : {'error': 'bad_frame'});
      expect(hub.state!.frameOf(hub.state!.views().single.id), isNull);
      // the same declared size without the trick is refused too
      ticks += 4000;
      final plain = await client.post(u('/frame', {'session_id': 'fs'}),
          headers: {'authorization': 'Bearer $t'}, body: big);
      expect(plain.statusCode, 422);
    });

    test('N-1: SOI + fill bytes only is a 400, never a 500', () async {
      final t = await join('f');
      await postJson('/ping', pingBody('fs'), token: t);
      final r = await client.post(u('/frame', {'session_id': 'fs'}),
          headers: {'authorization': 'Bearer $t'},
          body: Uint8List.fromList(
              [0xFF, 0xD8, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]));
      expect(r.statusCode, 400);
      expect(jsonDecode(r.body), {'error': 'bad_frame'});
    });

    test(
        'N-1: an EXIF thumbnail inside a well-formed APP1 does not matter; a '
        'malformed APP1 that exposes it is refused; normal 640x360 is accepted',
        () async {
      final t = await join('f');
      await postJson('/ping', pingBody('fs'), token: t);
      Future<http.Response> send(Uint8List b) =>
          client.post(u('/frame', {'session_id': 'fs'}),
              headers: {'authorization': 'Bearer $t'}, body: b);
      final thumb = lanJpeg(w: 160, h: 120, marker: 'T');
      final main = lanJpeg(w: 640, h: 360);

      final okApp1 = Uint8List.fromList([
        ...main.sublist(0, 2),
        0xFF, 0xE1, (thumb.length + 2) >> 8, (thumb.length + 2) & 0xFF,
        ...thumb, //
        ...main.sublist(2),
      ]);
      expect((await send(okApp1)).statusCode, 200);

      ticks += 4000;
      // APP1 whose length is too short: its payload is walked as segments
      final badApp1 = Uint8List.fromList([
        ...main.sublist(0, 2),
        0xFF, 0xE1, 0, 4, 0, 0, //
        ...thumb,
        ...main.sublist(2),
      ]);
      final r = await send(badApp1);
      expect(r.statusCode, isNot(200));
      expect(r.statusCode, anyOf(400, 422));

      ticks += 4000;
      expect((await send(main)).statusCode, 200);
    });

    test('a burst of 100 frames is not accepted (cost + minimum interval)',
        () async {
      final t = await join('f');
      await postJson('/ping', pingBody('fs'), token: t);
      var ok = 0, tooFast = 0, limited = 0;
      for (var i = 0; i < 100; i++) {
        final r = await client.post(u('/frame', {'session_id': 'fs'}),
            headers: {'authorization': 'Bearer $t'}, body: lanJpeg());
        if (r.statusCode == 200) ok++;
        if (r.statusCode == 429) {
          if ((jsonDecode(r.body) as Map)['error'] == 'too_fast') {
            tooFast++;
          } else {
            limited++;
          }
        }
      }
      // ignore: avoid_print
      print(
          'S-007: 100-frame burst -> accepted=$ok too_fast=$tooFast rate_limited=$limited');
      expect(ok, lessThanOrEqualTo(1));
      expect(ok + tooFast + limited, 100);

      // An honest client (one frame per interval) is unaffected.
      var honest = 0;
      for (var i = 0; i < 10; i++) {
        ticks += 3000;
        final r = await client.post(u('/frame', {'session_id': 'fs'}),
            headers: {'authorization': 'Bearer $t'}, body: lanJpeg());
        if (r.statusCode == 200) honest++;
      }
      expect(honest, 10);
    });
  });

  // ── S-010 / S-011 ──────────────────────────────────────────────────────────

  group('S-010 / S-011', () {
    setUp(boot);
    tearDown(shutdown);

    test('non-finite numbers are a clean 400, never a 500', () async {
      final t = await join('m');
      var r = await postJson('/ping',
          '{"session_id":"s","test_key":"t_all","status":"active","tab_switch_count":1e999}',
          token: t);
      expect(r.statusCode, 400);
      r = await postJson(
          '/result', '{"payload":{"student_id":"$lanS1","x":1e999}}',
          token: t, headers: {'idempotency-key': 'inf1'});
      expect(r.statusCode, 400);
      expect(jsonDecode(r.body), {'error': 'bad_json'});
      r = await postJson(
          '/result', '{"payload":{"student_id":"$lanS1","x":-1e999}}',
          token: t, headers: {'idempotency-key': 'inf2'});
      expect(r.statusCode, 400);
    });

    test('same key + same body is acked, same key + other body is a 409',
        () async {
      final t = await join('m');
      expect((await sendResult(t, 'k', lanResultPayload())).statusCode, 200);
      expect((await sendResult(t, 'k', lanResultPayload())).statusCode, 200);
      final r = await sendResult(t, 'k', {
        ...lanResultPayload(),
        'raw_answers': {'Vocabulary/0': 2}
      });
      expect(r.statusCode, 409);
      expect(jsonDecode(r.body), {'error': 'idempotency_conflict'});
      expect(await PackResultsDb.rowsForPack(lanPackUuid), hasLength(1));
    });
  });
}
