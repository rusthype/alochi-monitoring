// LAN hub (phase 3): the REAL shelf server on loopback, driven over HTTP.
//
// Covers decision 1 (class code + token + throttling), 2 (result chain,
// idempotency, roster/allow-list), 3 (proctoring reply shape, frames in
// memory only), 7 (limits, path traversal, no internals in errors).
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/local_server/hub_guard.dart';
import 'package:alochi_monitoring/core/local_server/hub_state.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/offline_crypto.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/core/services/heartbeat_service.dart';
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
  late MonitoredClock clock;
  late ShelfHub hub;
  late String base;
  late http.Client client;

  setUpAll(() {
    // flutter_test mocks dart:io HTTP (every call answers 400); these tests
    // need REAL loopback sockets.
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  Future<void> boot({int? maxResultsPerStudent}) async {
    client = http.Client();
    tmp = Directory.systemTemp.createTempSync('lan_hub_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    ticks = 1000000;
    clock = MonitoredClock(
        ticks: () => ticks, wall: () => 0, highWaterStore: _MemHwm());
    final media = makeMediaDir(tmp, _mediaSha);
    final session = await OfflinePackSession.open(
        lanTestPack(mediaRef: 'media/$_mediaSha.jpg'), media);
    hub = ShelfHub(session,
        bindAddress: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
        hubName: 'test-hub',
        clock: clock,
        maxResultsPerStudent:
            maxResultsPerStudent ?? HubLimits.maxResultsPerStudent);
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

  setUp(boot);
  tearDown(shutdown);

  Uri u(String path, [Map<String, String>? q]) =>
      Uri.parse('$base$path').replace(queryParameters: q);

  Future<http.Response> postJson(String path, Object? body,
      {String? token, Map<String, String> headers = const {}}) {
    return client.post(u(path),
        headers: {
          'content-type': 'application/json',
          if (token != null) 'authorization': 'Bearer $token',
          ...headers,
        },
        body: jsonEncode(body));
  }

  Future<http.Response> get(String path, String? token,
      [Map<String, String>? q]) {
    return client.get(u(path, q),
        headers: {if (token != null) 'authorization': 'Bearer $token'});
  }

  Future<String> join({String? code, String machine = 'machine-1'}) async {
    final r = await postJson('/join', {
      'code': code ?? hub.state!.code,
      'machine_id': machine,
      'device_name': 'PC $machine',
    });
    expect(r.statusCode, 200, reason: r.body);
    return (jsonDecode(r.body) as Map)['token'] as String;
  }

  Map<String, dynamic> pingBody(String session,
          {String student = lanS1, String testKey = 't_all'}) =>
      {
        'session_id': session,
        'name': 'Valiyev Ali',
        'test_key': testKey,
        'status': 'active',
        'student_code': student,
        'tab_switch_count': 2,
        'current_question_index': 1,
        'total_questions': 5,
        'capabilities': ['pause_lock', 'seat_id'],
        'device_name': 'PC-1',
      };

  Future<Map<String, dynamic>> ping(
      String token, Map<String, dynamic> body) async {
    final r = await postJson('/ping', body, token: token);
    expect(r.statusCode, 200, reason: r.body);
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Uint8List jpeg([String marker = 'FRAMEMARKER']) => lanJpeg(marker: marker);

  // ── decision 1: class code, token, throttling ─────────────────────────────

  group('join', () {
    test('class code is 6 random digits and compared in constant time', () {
      expect(hub.state!.code, matches(RegExp(r'^\d{6}$')));
      expect(constantTimeEquals('123456', '123456'), isTrue);
      expect(constantTimeEquals('123456', '123457'), isFalse);
      expect(constantTimeEquals('123456', '12345'), isFalse);
      expect(constantTimeEquals('', ''), isTrue);
    });

    test('wrong code -> 401; 5 misses block the IP (even for the right code)',
        () async {
      final wrong = hub.state!.code == '000000' ? '111111' : '000000';
      for (var i = 0; i < 5; i++) {
        final r = await postJson('/join', {'code': wrong, 'machine_id': 'm'});
        expect(r.statusCode, 401);
        expect(jsonDecode(r.body), {'error': 'bad_code'});
      }
      final blocked =
          await postJson('/join', {'code': hub.state!.code, 'machine_id': 'm'});
      expect(blocked.statusCode, 429);
      expect(blocked.headers['retry-after'], isNotNull);
      expect((jsonDecode(blocked.body) as Map)['error'], 'too_many_attempts');

      // The block is measured on the MONOTONIC clock: 61 s later it is gone.
      ticks += 61000;
      final ok =
          await postJson('/join', {'code': hub.state!.code, 'machine_id': 'm'});
      expect(ok.statusCode, 200);
    });

    test('a changed system date cannot lift the block (monotonic time only)',
        () async {
      final wrong = hub.state!.code == '000000' ? '111111' : '000000';
      for (var i = 0; i < 5; i++) {
        await postJson('/join', {'code': wrong, 'machine_id': 'm'});
      }
      // The hub never reads the wall clock: only monotonic ticks advance.
      ticks += 2000;
      final r =
          await postJson('/join', {'code': hub.state!.code, 'machine_id': 'm'});
      expect(r.statusCode, 429);
    });

    test('global ceiling: wrong codes from many sources slow everyone down',
        () {
      var t = 0;
      final gate = JoinFailureGate(
          ticks: () => t, maxFailures: 5, globalMaxFailures: 10);
      for (var i = 0; i < 10; i++) {
        gate.recordFailure('10.0.0.$i');
      }
      expect(gate.blockedForMs('10.9.9.9'), isNotNull);
      t += 61000;
      expect(gate.blockedForMs('10.9.9.9'), isNull);
    });

    test('join returns a 32-byte url-safe token and hub identity', () async {
      final r = await postJson('/join',
          {'code': hub.state!.code, 'machine_id': 'm1', 'device_name': 'PC1'});
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      expect(base64Url.decode(base64.normalize(j['token'] as String)),
          hasLength(32));
      expect(j['pack_uuid'], lanPackUuid);
      expect(j['school_code'], '999');
      expect(j['hub_name'], 'test-hub');
      // The pack PIN / chain key / class code never appear in a reply.
      expect(r.body, isNot(contains(hub.state!.code)));
    });

    test('the same PC joining again replaces its token', () async {
      final a = await join(machine: 'pc');
      final b = await join(machine: 'pc');
      expect(a, isNot(b));
      expect((await get('/groups', a)).statusCode, 401);
      expect((await get('/groups', b)).statusCode, 200);
      expect(hub.state!.clientCount, 1);
    });

    test('code rotation keeps existing tokens, new joins need the new code',
        () async {
      final t = await join();
      final old = hub.state!.code;
      hub.state!.rotateCode();
      expect(hub.state!.code, isNot(old));
      expect((await get('/groups', t)).statusCode, 200);
      final r = await postJson('/join', {'code': old, 'machine_id': 'x'});
      expect(r.statusCode, 401);
    });

    test('at most maxClients PCs; a known PC can still re-join', () {
      final st = HubState(
        packUuid: 'p',
        schoolId: 's',
        schoolCode: '1',
        hubName: 'h',
        groups: const [],
        students: const [],
        allowedTestKeys: const [],
        maxClients: 2,
      );
      JoinResult j(String m) =>
          st.join(ip: '1.1.1.1', code: st.code, machineId: m, deviceName: '');
      expect(j('a').outcome, JoinOutcome.ok);
      expect(j('b').outcome, JoinOutcome.ok);
      expect(j('c').outcome, JoinOutcome.full);
      expect(j('a').outcome, JoinOutcome.ok);
      expect(st.clientCount, 2);
      st.dispose();
    });

    test('one address cannot hold more than maxClientsPerIp slots', () {
      final st = HubState(
        packUuid: 'p',
        schoolId: 's',
        schoolCode: '1',
        hubName: 'h',
        groups: const [],
        students: const [],
        allowedTestKeys: const [],
      );
      JoinResult j(String ip, String m) =>
          st.join(ip: ip, code: st.code, machineId: m, deviceName: '');
      for (var i = 0; i < HubLimits.maxClientsPerIp; i++) {
        expect(j('10.0.0.5', 'm$i').outcome, JoinOutcome.ok);
      }
      expect(j('10.0.0.5', 'extra').outcome, JoinOutcome.full);
      // another address is unaffected, and a known PC may still re-join
      expect(j('10.0.0.6', 'other').outcome, JoinOutcome.ok);
      expect(j('10.0.0.5', 'm0').outcome, JoinOutcome.ok);
      st.dispose();
    });

    test('malformed join bodies are 400, never 500', () async {
      for (final body in <Object?>[
        [],
        'x',
        {'code': 1, 'machine_id': 'm'},
        {'code': '123456'},
        {'code': '123456', 'machine_id': 'has space'},
        {'code': '123456', 'machine_id': 'é' * 3},
      ]) {
        final r = await postJson('/join', body);
        expect(r.statusCode, 400, reason: '$body -> ${r.body}');
      }
    });
  });

  // ── auth ──────────────────────────────────────────────────────────────────

  group('auth', () {
    test('every endpoint but /health and /join needs a valid bearer token',
        () async {
      final reqs = <Future<http.Response>>[
        get('/groups', null),
        get('/students', null, {'group_id': lanG1}),
        get('/catalog', null),
        get('/test', null, {'key': 't_all'}),
        get('/packages', null),
        get('/package_questions', null, {'id': '42', 'variant': '1'}),
        get('/diagnostics', null),
        get('/media/$_mediaSha.jpg', null),
        postJson('/keepalive', {}),
        postJson('/ping', {}),
        postJson('/frame', {}),
        postJson('/result', {}),
        get('/groups', 'not-a-real-token'),
        client.get(u('/groups'), headers: {'authorization': 'Basic abc'}),
      ];
      for (final r in await Future.wait(reqs)) {
        expect(r.statusCode, 401, reason: r.request?.url.toString());
        expect(jsonDecode(r.body), {'error': 'unauthorized'});
      }
      expect((await get('/health', null)).statusCode, 200);
    });

    test('unauthenticated floods are rate limited per IP', () async {
      var limited = 0;
      for (var i = 0; i < 80; i++) {
        final r = await get('/groups', 'forged-$i');
        if (r.statusCode == 429) limited++;
      }
      expect(limited, greaterThan(0));
    });

    test('an authenticated flood hits the per-token limit, then recovers',
        () async {
      final t = await join();
      var limited = 0;
      for (var i = 0; i < 200; i++) {
        if ((await get('/groups', t)).statusCode == 429) limited++;
      }
      expect(limited, greaterThan(0));
      ticks += 5000; // monotonic refill
      expect((await get('/groups', t)).statusCode, 200);
    });

    test('errors never leak internals (no stack, paths, code, PIN, key)',
        () async {
      final t = await join();
      final bodies = <String>[];
      for (final r in [
        await postJson('/ping', [1, 2], token: t),
        await postJson('/result', {'payload': 1},
            token: t, headers: {'idempotency-key': 'k'}),
        await get('/test', t, {'key': 'nope'}),
        await get('/nonexistent', t),
        await postJson('/join', {'code': 'x'}),
      ]) {
        bodies.add(r.body);
      }
      for (final b in bodies) {
        expect(b, isNot(contains('Exception')));
        expect(b, isNot(contains('/Users')));
        expect(b, isNot(contains('.dart')));
        expect(b, isNot(contains(hub.state!.code)));
        expect(b, isNot(contains(t)));
      }
    });
  });

  // ── content ───────────────────────────────────────────────────────────────

  group('content', () {
    test('roster, catalog, test body, packages and media', () async {
      final t = await join();
      final groups = jsonDecode((await get('/groups', t)).body) as List;
      expect(groups.map((g) => g['name']), ['5-A | Ingliz', '6-B']);

      final students =
          jsonDecode((await get('/students', t, {'group_id': lanG1})).body)
              as List;
      expect(students.single['id'], lanS1);

      final cat =
          jsonDecode((await get('/catalog', t, {'group_id': lanG2})).body)
              as List;
      expect(cat.map((e) => e['test_key']), ['t_all']); // t_g1_only filtered
      final cat1 =
          jsonDecode((await get('/catalog', t, {'group_id': lanG1})).body)
              as List;
      expect(cat1.map((e) => e['test_key']).toSet(), {'t_all', 't_g1_only'});

      final test = await get('/test', t, {'key': 't_all'});
      expect(test.statusCode, 200);
      final data = jsonDecode(test.body) as Map<String, dynamic>;
      expect(data['test_key'], 't_all');
      expect(test.body, isNot(contains('"ans"'))); // no answer key in a pack
      expect((await get('/test', t, {'key': 'zzz'})).statusCode, 404);

      final pk = jsonDecode((await get('/packages', t)).body) as List;
      expect(pk.single['id'], '42');
      final qs = jsonDecode(
          (await get('/package_questions', t, {'id': '42', 'variant': '1'}))
              .body) as Map;
      expect((qs['questions'] as List).single['id'], 'q1');

      final diag = jsonDecode((await get('/diagnostics', t)).body) as Map;
      expect((diag['tests'] as List).single['key'], 'diag:math:g5:uz:v1');

      final m = await get('/media/$_mediaSha.jpg', t);
      expect(m.statusCode, 200);
      expect(m.bodyBytes, lanMediaBytes);
      expect(m.headers['content-type'], 'image/jpeg');
      expect(m.headers['x-content-type-options'], 'nosniff');
    });

    test('media: only <sha256>.<ext> names; traversal is refused', () async {
      final t = await join();
      // A file the traversal would reach if it worked.
      File(p.join(tmp.path, 'secret.txt')).writeAsStringSync('TOPSECRET');
      File(p.join(tmp.path, 'media', 'plain.jpg')).writeAsBytesSync([1]);
      final raw = HttpClient();
      addTearDown(raw.close);
      for (final path in [
        '/media/..%2Fsecret.txt',
        '/media/%2e%2e%2fsecret.txt',
        '/media/..%5Csecret.txt',
        '/media/plain.jpg',
        '/media/$_mediaSha.exe',
        '/media/${_mediaSha.toUpperCase()}.jpg',
        '/media/${_mediaSha.substring(1)}.jpg',
        '/media/$_mediaSha.jpg%00.png',
        '/media/${'0' * 64}.jpg', // well-formed but absent
      ]) {
        final req = await raw.getUrl(Uri.parse('$base$path'));
        req.headers.set('authorization', 'Bearer $t');
        final resp = await req.close();
        final body = await utf8.decodeStream(resp);
        expect(resp.statusCode, 404, reason: path);
        expect(body, isNot(contains('TOPSECRET')));
      }
    });
  });

  // ── decision 7: limits ────────────────────────────────────────────────────

  group('limits', () {
    test('body ceilings: join 1 KB, ping 64 KB, frame 512 KB, result 1 MB',
        () async {
      final t = await join();
      Uint8List big(int n) => Uint8List(n)..fillRange(0, n, 0x61);

      var r = await client.post(u('/join'), body: big(HubLimits.joinBody + 1));
      expect(r.statusCode, 413);
      r = await client.post(u('/ping'),
          headers: {'authorization': 'Bearer $t'},
          body: big(HubLimits.pingBody + 1));
      expect(r.statusCode, 413);
      r = await client.post(u('/frame', {'session_id': 's'}),
          headers: {'authorization': 'Bearer $t'},
          body: big(HubLimits.frameBody + 1));
      expect(r.statusCode, 413);
      r = await client.post(u('/result'),
          headers: {'authorization': 'Bearer $t', 'idempotency-key': 'k'},
          body: big(HubLimits.resultBody + 1));
      expect(r.statusCode, 413);
    });

    test('a request without Content-Length (chunked) is refused', () async {
      final raw = HttpClient();
      addTearDown(raw.close);
      final req = await raw.postUrl(Uri.parse('$base/join'));
      req.contentLength = -1;
      req.headers.chunkedTransferEncoding = true;
      req.write(jsonEncode({'code': hub.state!.code, 'machine_id': 'm'}));
      final resp = await req.close();
      await resp.drain<void>();
      expect(resp.statusCode, 411);
    });

    test('JSON depth / shape bombs are 400 (no crash, hub keeps serving)',
        () async {
      final t = await join();
      final deep = '${'{"a":' * 200}1${'}' * 200}';
      var r = await client.post(u('/ping'),
          headers: {'authorization': 'Bearer $t'}, body: deep);
      expect(r.statusCode, 400);
      final deepList = '${'[' * 30000}${']' * 30000}';
      r = await client.post(u('/ping'),
          headers: {'authorization': 'Bearer $t'}, body: deepList);
      expect(r.statusCode, 400);
      r = await client.post(u('/ping'),
          headers: {'authorization': 'Bearer $t'}, body: 'not json {{{');
      expect(r.statusCode, 400);
      r = await client.post(u('/ping'),
          headers: {'authorization': 'Bearer $t'},
          body: Uint8List.fromList([0xff, 0xfe, 0x7b]));
      expect(r.statusCode, 400);
      expect((await get('/groups', t)).statusCode, 200);
    });

    test('ping fields are type/size checked', () async {
      final t = await join();
      for (final bad in <Map<String, dynamic>>[
        {'session_id': 's' * 65},
        {'session_id': 5},
        {'session_id': 's', 'tab_switch_count': -1},
        {'session_id': 's', 'tab_switch_count': 'x'},
        {'session_id': 's', 'status': 'weird'},
        {'session_id': 's', 'current_question_index': 1e12},
      ]) {
        final r = await postJson('/ping', bad, token: t);
        expect(r.statusCode, 400, reason: '$bad');
      }
    });
  });

  // ── decision 2: results ───────────────────────────────────────────────────

  group('results', () {
    Future<http.Response> sendResult(
        String t, String key, Map<String, dynamic> payload,
        {List<dynamic>? incidents, List<dynamic>? flags}) {
      return postJson(
          '/result',
          {
            'payload': payload,
            if (incidents != null) 'incidents': incidents,
            if (flags != null) 'clock_flags': flags,
          },
          token: t,
          headers: {'idempotency-key': key});
    }

    test('a valid result joins the pack chain and is acknowledged', () async {
      final t = await join();
      final r = await sendResult(t, 'key-1', lanResultPayload(), incidents: [
        {'type': 'focus_lost', 'at': '2026-10-17T09:10:00Z'}
      ]);
      expect(r.statusCode, 200);
      expect(jsonDecode(r.body), {'ok': true});

      final rows = await PackResultsDb.rowsForPack(lanPackUuid);
      expect(rows, hasLength(1));
      expect(rows.single.idempotencyKey, 'key-1');
      expect(jsonDecode(rows.single.payloadJson)['student_id'], lanS1);
      expect(rows.single.prevHash, '0' * 64);
      // The chain link is the HMAC the exporter/server will recompute.
      expect(
          rows.single.hash,
          OfflineCrypto.chainHash(
              OfflinePackSession.current!.pack.chainKey,
              rows.single.prevHash,
              rows.single.payloadJson,
              rows.single.metaJson));
      final meta = jsonDecode(rows.single.metaJson) as Map;
      expect(meta['idempotency_key'], 'key-1');
      expect((meta['incidents'] as List).first['type'], 'focus_lost');
      expect((meta['incidents'] as List).last['type'], 'lan_client');
      expect(hub.state!.resultsAccepted, 1);
    });

    test('resending the same Idempotency-Key acks again but writes no 2nd row',
        () async {
      final t = await join();
      expect((await sendResult(t, 'dup', lanResultPayload())).statusCode, 200);
      expect((await sendResult(t, 'dup', lanResultPayload())).statusCode, 200);
      // A DIFFERENT body under the same key is never silently "acked" (S-011).
      final other = await sendResult(
          t, 'dup', lanResultPayload(student: lanS2, group: lanG2));
      expect(other.statusCode, 409);
      expect(jsonDecode(other.body), {'error': 'idempotency_conflict'});
      expect(await PackResultsDb.rowsForPack(lanPackUuid), hasLength(1));
      expect(hub.state!.resultsAccepted, 1);
    });

    test('roster and allow-list: refused, nothing written', () async {
      final t = await join();
      var r = await sendResult(t, 'a',
          lanResultPayload(student: '00000000-0000-4000-8000-0000000000ff'));
      expect(r.statusCode, 422);
      expect(jsonDecode(r.body),
          {'error': 'rejected', 'reason': 'student_invalid'});

      // Student exists but not in that group.
      r = await sendResult(t, 'b', lanResultPayload(group: lanG2));
      expect((jsonDecode(r.body) as Map)['reason'], 'student_invalid');

      r = await sendResult(
          t, 'c', lanResultPayload(testKey: 'some_other_test'));
      expect(r.statusCode, 422);
      expect((jsonDecode(r.body) as Map)['reason'], 'test_not_in_pack');

      // payload.test_key and detail.test_key are both checked.
      r = await sendResult(
          t, 'd', {...lanResultPayload(), 'test_key': 'diag:english:g9:uz:v9'});
      expect((jsonDecode(r.body) as Map)['reason'], 'test_not_in_pack');

      r = await sendResult(t, 'e', {...lanResultPayload(), 'student_id': 7});
      expect((jsonDecode(r.body) as Map)['reason'], 'student_invalid');

      expect(await PackResultsDb.rowsForPack(lanPackUuid), isEmpty);

      // The pack's own diagnostic and package keys ARE allowed.
      r = await sendResult(
          t, 'f', lanResultPayload(testKey: 'diag:math:g5:uz:v1'));
      expect(r.statusCode, 200);
      r = await sendResult(t, 'g', lanResultPayload(testKey: 'package:42:v1'));
      expect(r.statusCode, 200);
    });

    test('Idempotency-Key header is mandatory and well formed', () async {
      final t = await join();
      for (final k in ['', 'a b', 'x' * 65, 'a/b']) {
        final r = await postJson('/result', {'payload': lanResultPayload()},
            token: t, headers: {if (k.isNotEmpty) 'idempotency-key': k});
        expect(r.statusCode, 400, reason: k);
      }
    });

    test('client incident lists are capped to what the server will keep',
        () async {
      final t = await join();
      final many = [
        for (var i = 0; i < 400; i++) {'type': 'focus_lost', 'n': i},
        {'type': 'fat', 'blob': 'x' * 5000}, // > 1 KiB item
        'junk',
      ];
      expect(
          (await sendResult(t, 'cap', lanResultPayload(),
                  incidents: many, flags: many))
              .statusCode,
          200);
      final meta = jsonDecode(
              (await PackResultsDb.rowsForPack(lanPackUuid)).single.metaJson)
          as Map;
      final inc = meta['incidents'] as List;
      final flags = meta['clock_flags'] as List;
      expect(inc.length, lessThanOrEqualTo(201)); // server MAX_INCIDENTS
      expect(flags.length, lessThanOrEqualTo(101)); // server MAX_CLOCK_FLAGS
      expect(inc.any((e) => e['type'] == 'incident_overflow'), isTrue);
      expect(inc.where((e) => e['type'] == 'fat'), isEmpty);
    });

    test('a client cannot flood the chain: per-PC quota', () async {
      // (the per-student cap is lifted: this test is about the address quota)
      await shutdown();
      await boot(maxResultsPerStudent: 1 << 20);
      final t = await join();
      var accepted = 0;
      int? refused;
      for (var i = 0; i < HubLimits.maxResultsPerIp + 1; i++) {
        ticks += 1000; // keep the token bucket full
        final r = await sendResult(t, 'q$i', lanResultPayload());
        if (r.statusCode == 200) {
          accepted++;
        } else {
          refused = r.statusCode;
        }
      }
      expect(accepted, HubLimits.maxResultsPerIp);
      expect(refused, 403);
      // A repeat of an ALREADY stored key is still acknowledged.
      expect((await sendResult(t, 'q0', lanResultPayload())).statusCode, 200);
      // 151 sequential, individually fsync'd chain writes: seconds on a Mac,
      // but a slow Windows CI disk exceeded the default 30 s once (the hub
      // answered every request; only the clock ran out).
    }, timeout: const Timeout(Duration(minutes: 3)));

    test('a finished result ends the PC\'s test attempt and drops its frame',
        () async {
      final t = await join();
      await ping(t, pingBody('S1'));
      final id = hub.state!.views().single.id;
      expect(hub.state!.views().single.inTest, isTrue);
      await client.post(u('/frame', {'session_id': 'S1'}),
          headers: {'authorization': 'Bearer $t'}, body: jpeg());
      expect(hub.state!.frameOf(id), isNotNull);

      await sendResult(t, 'done', lanResultPayload());
      expect(hub.state!.views().single.inTest, isFalse);
      expect(hub.state!.frameOf(id), isNull);
    });
  });

  // ── decision 3: proctoring ────────────────────────────────────────────────

  group('proctoring', () {
    test('ping reply carries what reconcileProctorState consumes', () async {
      final t = await join();
      var j = await ping(t, pingBody('S1'));
      expect(j['locked'], false);
      expect(j['extra_time_seconds'], 0);
      expect(j['terminated'], false);
      expect(j['conflict'], false);
      expect(j['proctor_token'], isA<String>());
      expect((j['proctor_token'] as String), isNotEmpty);
      expect(j['proctor_interval_ms'], inInclusiveRange(1000, 30000));
      expect(j['commands'], isA<List>());

      final id = hub.state!.views().single.id;

      // Drive the REAL client reconciler with the hub's replies.
      final locks = <bool>[];
      final extras = <int>[];
      final hb = HeartbeatService.instance
        ..onLockChanged = locks.add
        ..onExtendSeconds = extras.add;
      addTearDown(() {
        hb.onLockChanged = null;
        hb.onExtendSeconds = null;
        hb.reconcileProctorState(locked: false, extraTimeSeconds: 0);
      });
      void feed(Map<String, dynamic> r) => hb.reconcileProctorState(
            locked: r['locked'] as bool?,
            extraTimeSeconds: r['extra_time_seconds'] as int?,
            commands: r['commands'] as List<dynamic>?,
          );
      feed(j);
      expect(locks, isEmpty);
      expect(extras, isEmpty);

      hub.state!.setLocked(id, true);
      j = await ping(t, pingBody('S1'));
      expect(j['locked'], true);
      feed(j);
      expect(locks, [true]);
      feed(await ping(t, pingBody('S1'))); // duplicate reply: idempotent
      expect(locks, [true]);

      hub.state!.addExtraTime(id, 300);
      j = await ping(t, pingBody('S1'));
      expect(j['extra_time_seconds'], 300); // running TOTAL, not a delta
      feed(j);
      hub.state!.addExtraTime(id, 60);
      j = await ping(t, pingBody('S1'));
      expect(j['extra_time_seconds'], 360);
      feed(j);
      expect(extras, [300, 60]); // the client diffs the totals itself

      hub.state!.setLocked(id, false);
      feed(await ping(t, pingBody('S1')));
      expect(locks, [true, false]);
    });

    test('finish-test command: terminated is true for THAT attempt only',
        () async {
      final t = await join();
      await ping(t, pingBody('S1'));
      final id = hub.state!.views().single.id;
      hub.state!.terminate(id);
      expect((await ping(t, pingBody('S1')))['terminated'], true);
      // A new attempt (new session id) starts clean.
      final j = await ping(t, pingBody('S2'));
      expect(j['terminated'], false);
      expect(j['locked'], false);
      expect(j['extra_time_seconds'], 0);
    });

    test('pause / extra time only apply while the PC is in a test', () async {
      final t = await join();
      await ping(t, {...pingBody('dev'), 'test_key': ''}); // idle ping
      final id = hub.state!.views().single.id;
      hub.state!.setLocked(id, true);
      hub.state!.addExtraTime(id, 60);
      final j = await ping(t, {...pingBody('dev'), 'test_key': ''});
      expect(j['locked'], false);
      expect(j['extra_time_seconds'], 0);
    });

    test(
        'one student on two PCs: the newcomer gets conflict:true, the holder '
        'is never ended on its own (S-003)', () async {
      final a = await join(machine: 'pc-a');
      final b = await join(machine: 'pc-b');
      Map<String, dynamic> as(String sid, String dev,
              {String student = lanS1}) =>
          {...pingBody(sid, student: student), 'device_name': dev};
      expect((await ping(a, as('A1', 'pc-a')))['conflict'], false);
      expect((await ping(b, as('B1', 'pc-b')))['conflict'], true);
      // The refused PC holds nothing; a different student is fine.
      expect(
          (await ping(b, as('B2', 'pc-b', student: lanS2)))['conflict'], false);

      // The holder goes silent for a long time (a flaky link, or a flood
      // aimed at it): the newcomer still does NOT get the seat and the holder
      // is not told to stop. Only the teacher decides.
      ticks += 120000;
      expect((await ping(b, as('B3', 'pc-b')))['conflict'], true);
      final aReply = await ping(a, as('A1', 'pc-a'));
      expect(aReply['terminated'], false);
      expect(aReply['conflict'], false);
      final open = hub.state!.conflicts();
      expect(open, hasLength(1));
      expect(open.single.studentName, 'Valiyev Ali');
      expect(open.single.holder.deviceName, contains('pc-a'));
      expect(open.single.claimant.deviceName, contains('pc-b'));
    });

    test(
        'teacher: "release the old one" ends the holder, then the claimant '
        'gets the seat', () async {
      final a = await join(machine: 'pc-a');
      final b = await join(machine: 'pc-b');
      await ping(a, pingBody('A1'));
      expect((await ping(b, pingBody('B1')))['conflict'], true);
      hub.state!.resolveConflict(hub.state!.conflicts().single.id,
          releaseHolder: true);
      expect((await ping(a, pingBody('A1')))['terminated'], true);
      expect((await ping(b, pingBody('B2')))['conflict'], false);
      expect(hub.state!.conflicts(), isEmpty);
    });

    test(
        'teacher: "reject the new one" keeps the holder; the claim stays '
        'refused and is not re-reported', () async {
      final a = await join(machine: 'pc-a');
      final b = await join(machine: 'pc-b');
      await ping(a, pingBody('A1'));
      expect((await ping(b, pingBody('B1')))['conflict'], true);
      hub.state!.resolveConflict(hub.state!.conflicts().single.id,
          releaseHolder: false);
      expect((await ping(a, pingBody('A1')))['terminated'], false);
      expect((await ping(b, pingBody('B2')))['conflict'], true);
      expect(hub.state!.conflicts(), isEmpty); // no new banner
      // ... for a while only.
      ticks += HubLimits.rejectedClaimMs + 1000;
      await ping(a, {...pingBody('A1'), 'test_key': ''}); // holder finishes
      expect((await ping(b, pingBody('B3')))['conflict'], false);
    });

    test(
        'squatting on a student id: the victim shows up on the teacher\'s '
        'banner with both PCs named', () async {
      final atk = await join(machine: 'atk');
      final vic = await join(machine: 'vic');
      await ping(
          atk, pingBody('atk-sess')); // claims S1 while the real one is idle
      expect((await ping(vic, pingBody('vic-sess')))['conflict'], true);
      ticks += 20000;
      await postJson('/keepalive', {}, token: vic); // the victim stays alive
      expect((await ping(vic, pingBody('vic-sess')))['conflict'], true);
      expect((await ping(atk, pingBody('atk-sess')))['terminated'], false);
      expect(hub.state!.conflicts(), hasLength(1));
    });

    test('diagnostic pings (DIAG-offline|student|group|lang) are identified',
        () async {
      final a = await join(machine: 'pc-a');
      final b = await join(machine: 'pc-b');
      Map<String, dynamic> diag(String sid) => {
            'session_id': sid,
            'name': 'Valiyev Ali',
            'test_key': 'diag_offline|$lanS1|$lanG1|uz',
            'status': 'active',
            'student_code': 'DIAG-offline|$lanS1|$lanG1|uz',
          };
      expect((await ping(a, diag('D1')))['conflict'], false);
      expect(hub.state!.views().firstWhere((v) => v.inTest).className,
          '5-A | Ingliz');
      expect((await ping(b, diag('D2')))['conflict'], true);
    });

    test('late "finished" ping of an ended attempt does not reopen it',
        () async {
      final t = await join();
      await ping(t, pingBody('S1'));
      await postJson('/result', {'payload': lanResultPayload()},
          token: t, headers: {'idempotency-key': 'r1'});
      expect(hub.state!.views().single.inTest, isFalse);
      await ping(t, {...pingBody('S1'), 'status': 'finished'});
      expect(hub.state!.views().single.inTest, isFalse);
    });

    test('frames live in memory only: nothing on disk, gone on stop', () async {
      final t = await join();
      await ping(t, pingBody('S1'));
      final id = hub.state!.views().single.id;
      final before = tmp
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toSet();

      var r = await client.post(
          u('/frame', {
            'session_id': 'S1',
            'frame_type': 'keyframe',
            'focus': 'true',
            'monitor_count': '1',
            'q_idx': '2',
            'total': '5',
          }),
          headers: {'authorization': 'Bearer $t'},
          body: jpeg('FRAMEMARKER-unique-123'));
      expect(r.statusCode, 200);
      final reply = jsonDecode(r.body) as Map;
      expect(reply.containsKey('locked'), isTrue);
      expect(reply.containsKey('extra_time_seconds'), isTrue);
      expect(hub.state!.frameOf(id), isNotNull);
      expect(hub.state!.views().single.questionNumber, 3);

      // Disk: no new file anywhere, and no file contains the pixels.
      final after = tmp
          .listSync(recursive: true)
          .whereType<File>()
          .map((f) => f.path)
          .toSet();
      expect(after.difference(before), isEmpty);
      for (final f in tmp.listSync(recursive: true).whereType<File>()) {
        expect(utf8.decode(f.readAsBytesSync(), allowMalformed: true),
            isNot(contains('FRAMEMARKER-unique-123')),
            reason: f.path);
      }

      // Patches are not stored (nothing to patch); junk and stale are refused.
      final keep = hub.state!.frameOf(id);
      ticks += 4000; // frames may not come faster than half the interval
      r = await client.post(
          u('/frame', {'session_id': 'S1', 'frame_type': 'patch'}),
          headers: {'authorization': 'Bearer $t'},
          body: jpeg('PATCH'));
      expect(r.statusCode, 200);
      expect(identical(hub.state!.frameOf(id), keep), isTrue);
      r = await client.post(u('/frame', {'session_id': 'S1'}),
          headers: {'authorization': 'Bearer $t'},
          body: Uint8List.fromList(utf8.encode('<html>not a jpeg</html>')));
      expect(r.statusCode, 400);
      r = await client.post(u('/frame', {'session_id': 'OTHER'}),
          headers: {'authorization': 'Bearer $t'}, body: jpeg());
      expect(r.statusCode, 409);

      // Watching a PC asks it for fresh keyframes at the larger profile.
      hub.state!.watch(id);
      final w = await ping(t, pingBody('S1'));
      expect(w['target_width'], 960);
      expect(
          (w['commands'] as List).any((c) => c['action'] == 'request_keyframe'),
          isTrue);
      hub.state!.watch(null);

      await hub.stop();
      expect(hub.state!.frameOf(id), isNull);
      expect(hub.state!.clientCount, 0);
    });

    test('teacher table: status, progress, remaining time, silence', () async {
      final t = await join();
      await ping(t, pingBody('S1'));
      var v = hub.state!.views().single;
      expect(v.status, ClientStatus.testing);
      expect(v.name, 'Valiyev Ali');
      expect(v.className, '5-A | Ingliz');
      expect(v.questionNumber, 2);
      expect(v.totalQuestions, 5);
      expect(v.tabSwitchCount, 2);
      expect(v.remainingSeconds, 30 * 60); // duration_minutes: 30

      ticks += 10000;
      hub.state!.addExtraTime(v.id, 300);
      v = hub.state!.views().single;
      expect(v.remainingSeconds, 30 * 60 + 300 - 10);

      ticks += 20000; // > 15 s of silence
      expect(hub.state!.views().single.status, ClientStatus.noContact);
      await postJson('/keepalive', {}, token: t);
      expect(hub.state!.views().single.status, ClientStatus.testing);
    });
  });

  // ── lifecycle ─────────────────────────────────────────────────────────────

  group('lifecycle', () {
    test('the hub refuses to start without an open pack session', () async {
      final session = OfflinePackSession.current!;
      await hub.stop();
      OfflinePackSession.close();
      final h2 = ShelfHub(session,
          bindAddress: InternetAddress.loopbackIPv4, firstPort: 0, lastPort: 0);
      await expectLater(
          h2.start(announce: false),
          throwsA(isA<HubStartException>()
              .having((e) => e.code, 'code', HubStartError.notActive)));
      // re-open so tearDown has something to close
      await OfflinePackSession.open(
          lanTestPack(), Directory(p.join(tmp.path, 'media2')));
    });

    test('closing the pack session stops the hub and drops every token',
        () async {
      final t = await join();
      expect((await get('/groups', t)).statusCode, 200);
      OfflinePackSession.close();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(hub.running, isFalse);
      expect(hub.state!.clientCount, 0);
      // Re-open so tearDown has something to close.
      await OfflinePackSession.open(
          lanTestPack(), Directory(p.join(tmp.path, 'media3')));
    });

    test('a busy port moves the hub to the next free one and says so',
        () async {
      final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(taken.close);
      final session = OfflinePackSession.current!;
      final h2 = ShelfHub(session,
          bindAddress: InternetAddress.loopbackIPv4,
          firstPort: taken.port,
          lastPort: taken.port + 20,
          clock: clock);
      await h2.start(announce: false);
      addTearDown(() async {
        await h2.stop();
        h2.dispose();
        ShelfHub.current = null;
      });
      expect(h2.port, isNot(taken.port));
      expect(h2.portWasFallback, isTrue);
    });

    test('no free port in the range -> portUnavailable', () async {
      final taken = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(taken.close);
      final h2 = ShelfHub(OfflinePackSession.current!,
          bindAddress: InternetAddress.loopbackIPv4,
          firstPort: taken.port,
          lastPort: taken.port,
          clock: clock);
      await expectLater(
          h2.start(announce: false),
          throwsA(isA<HubStartException>()
              .having((e) => e.code, 'code', HubStartError.portUnavailable)));
    });

    test('a restarted hub has a new code and does not know old tokens',
        () async {
      final t = await join();
      final oldCode = hub.state!.code;
      await hub.stop();
      await hub.start(announce: false);
      base = 'http://127.0.0.1:${hub.port}';
      expect((await get('/groups', t)).statusCode, 401);
      // (1-in-a-million collision aside)
      expect(hub.state!.code == oldCode, isFalse);
    });
  });
}
