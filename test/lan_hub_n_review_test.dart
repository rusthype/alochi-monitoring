// Regression tests for the T2 RE-review of the LAN hub (N-2, N-3, N-6 and the
// clock-flag / teacher-result accounting): every probe of the reviewer is
// repeated here. N-1 (frames) lives in lan_hub_review_test.dart, N-4 in
// lan_client_test.dart, N-5 and the banner overflow in lan_screens_test.dart.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/local_server/hub_guard.dart';
import 'package:alochi_monitoring/core/local_server/hub_state.dart';
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

/// A store whose high-water mark lies in the future: every check raises a flag.
class _FutureHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => DateTime.utc(2099);
  @override
  Future<void> write(DateTime utc) async {}
}

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
    int extraStudents = 0,
    int? maxPackPlainBytes,
    bool liftIpQuota = false,
    HighWaterStore? hwm,
  }) async {
    client = http.Client();
    tmp = Directory.systemTemp.createTempSync('lan_nrev_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    ticks = 1000000;
    clock = MonitoredClock(
        ticks: () => ticks, wall: () => 0, highWaterStore: hwm ?? _MemHwm());
    final session = await OfflinePackSession.open(
        lanTestPack(extraStudents: extraStudents),
        Directory(p.join(tmp.path, 'media'))..createSync());
    hub = ShelfHub(session,
        bindAddress: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
        hubName: 'test-hub',
        clock: clock,
        maxPackPlainBytes: maxPackPlainBytes ?? HubLimits.maxPackPlainBytes,
        // Many hostile addresses = no address quota that matters.
        maxResultsPerIp: liftIpQuota ? 1000000 : HubLimits.maxResultsPerIp,
        maxResultBytesPerIp:
            liftIpQuota ? 1 << 30 : HubLimits.maxResultBytesPerIp);
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

  Uri u(String path) => Uri.parse('$base$path');

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

  /// A valid result of [student] padded with [n] backslashes: the request body
  /// carries 2n bytes, the export entry ~4n (JSON escapes each one twice).
  Map<String, dynamic> poisonedFor(String student, String group, int n) => {
        ...lanResultPayload(student: student, group: group),
        'junk': List.filled(n, r'\').join()
      };

  Future<int> exportBytes() async =>
      (await PackResultsDb.chainUsage(lanPackUuid)).bytes;

  // ── N-2 ────────────────────────────────────────────────────────────────────

  group('N-2 pack-filling DoS', () {
    tearDown(shutdown);

    test('the request body limit is 64 KB', () async {
      await boot();
      expect(HubLimits.resultBody, 64 * 1024);
      final t = await join('m');
      final r = await sendResult(t, 'big',
          {...lanResultPayload(), 'junk': 'x' * (HubLimits.resultBody + 1)});
      expect(r.statusCode, 413);
    });

    test(
        'hostile PCs (any number of addresses) cannot fill the pack: the '
        'reserve for students without a result stays free and honest results '
        'are still accepted', () async {
      const budget = 450 * 1024;
      await boot(
          extraStudents: 4, maxPackPlainBytes: budget, liftIpQuota: true);
      // 6 roster students; the attackers send as S1, S2 and X0 only. Four
      // tokens stand for four addresses (the 2.5 MiB address quota is lifted).
      final tokens = [for (var i = 0; i < 4; i++) await join('atk$i')];
      final victims = [
        (lanS1, lanG1),
        (lanS2, lanG2),
        (lanExtraStudent(0), lanG1)
      ];
      final codes = <int, int>{};
      var n = 0;
      for (final (sid, gid) in victims) {
        for (var k = 0; k < 4; k++) {
          final r = await sendResult(tokens[n % 4], 'atk-${n++}',
              poisonedFor(sid, gid, 20 * 1024)); // ~82 KB of export each
          codes[r.statusCode] = (codes[r.statusCode] ?? 0) + 1;
        }
      }
      // ignore: avoid_print
      print('N-2 attack statuses: $codes, export=${await exportBytes()} B');
      expect(codes[507], greaterThan(0), reason: 'the pack-full path was hit');
      expect(codes[403], greaterThan(0), reason: 'the per-student cap was hit');
      final used = await exportBytes();
      expect(used, lessThanOrEqualTo(budget));
      // three roster students (X1..X3) still have no result: their room is free
      expect(
          budget - used, greaterThanOrEqualTo(3 * HubLimits.reservePerStudent));

      for (var i = 1; i <= 3; i++) {
        final r = await sendResult(tokens[i], 'honest-$i',
            lanResultPayload(student: lanExtraStudent(i), group: lanG1));
        expect(r.statusCode, 200, reason: 'honest X$i: ${r.body}');
      }
      expect(await exportBytes(), lessThanOrEqualTo(budget));
    });

    test('per-student cap: 3 results and 192 KB, other students unaffected',
        () async {
      await boot();
      final t = await join('m');
      for (var i = 0; i < HubLimits.maxResultsPerStudent; i++) {
        expect(
            (await sendResult(t, 'c$i', lanResultPayload())).statusCode, 200);
      }
      var r = await sendResult(t, 'c-over', lanResultPayload());
      expect(r.statusCode, 403);
      expect(jsonDecode(r.body), {'error': 'student_quota'});
      // an already stored key is still acknowledged
      expect((await sendResult(t, 'c0', lanResultPayload())).statusCode, 200);

      // bytes: two ~82 KB entries fit under 192 KB, a third does not
      const s2 = (lanS2, lanG2);
      expect(
          (await sendResult(t, 'b0', poisonedFor(s2.$1, s2.$2, 20 * 1024)))
              .statusCode,
          200);
      expect(
          (await sendResult(t, 'b1', poisonedFor(s2.$1, s2.$2, 20 * 1024)))
              .statusCode,
          200);
      r = await sendResult(t, 'b2', poisonedFor(s2.$1, s2.$2, 20 * 1024));
      expect(r.statusCode, 403);
      expect(jsonDecode(r.body), {'error': 'student_quota'});
    });

    test('the per-student tally survives a hub restart (read from the chain)',
        () async {
      await boot();
      var t = await join('m');
      for (var i = 0; i < HubLimits.maxResultsPerStudent; i++) {
        expect(
            (await sendResult(t, 'c$i', lanResultPayload())).statusCode, 200);
      }
      await hub.stop();
      await hub.start(announce: false);
      base = 'http://127.0.0.1:${hub.port}';
      t = await join('m2');
      final r = await sendResult(t, 'after', lanResultPayload());
      expect(r.statusCode, 403);
      expect(jsonDecode(r.body), {'error': 'student_quota'});
      expect(
          (await sendResult(
                  t, 's2', lanResultPayload(student: lanS2, group: lanG2)))
              .statusCode,
          200);
    });

    test(
        'results written by the teacher\'s own session and by the hub are '
        'counted in one critical section; the running figure is the real one',
        () async {
      await boot();
      final session = OfflinePackSession.current!;
      final t = await join('m');
      expect((await sendResult(t, 'h0', lanResultPayload())).statusCode, 200);
      expect(session.chainUsage, isNotNull);

      final mixed = await Future.wait<Object?>([
        for (var i = 0; i < 6; i++)
          i.isEven
              ? sendResult(
                  t, 'h-par-$i', lanResultPayload(student: lanS2, group: lanG2))
              : session.recordResult(
                  lanResultPayload(student: lanS2, group: lanG2),
                  token: 'own-$i'),
      ]);
      expect(mixed, hasLength(6));
      // a repeat of the teacher's own key is not counted twice
      await session.recordResult(lanResultPayload(), token: 'own-1');

      final fresh = await PackResultsDb.chainUsage(lanPackUuid);
      final running = session.chainUsage!;
      expect(running.bytes, fresh.bytes);
      expect(running.count, fresh.count);
      expect(running.perStudent, fresh.perStudent);
    });
  });

  // ── clock flags ────────────────────────────────────────────────────────────

  test('pendingFlags shows what drainFlags will return, overflow included',
      () async {
    final c = MonitoredClock(
        ticks: () => 1, wall: () => 0, highWaterStore: _FutureHwm());
    for (var i = 0; i < 105; i++) {
      await c.checkHighWaterMark();
    }
    final pending = c.pendingFlags;
    expect(pending, hasLength(101));
    expect(pending.last, {'type': 'clock_flags_overflow', 'dropped': 5});
    expect(c.drainFlags(), pending);
    expect(c.pendingFlags, isEmpty);
  });

  group('clock_flags_overflow is part of the measured entry', () {
    tearDown(shutdown);

    test('the hub\'s size figure equals the exporter\'s with an overflow item',
        () async {
      await boot(hwm: _FutureHwm());
      for (var i = 0; i < 105; i++) {
        await clock.checkHighWaterMark();
      }
      final t = await join('m');
      expect((await sendResult(t, 'f0', lanResultPayload())).statusCode, 200);
      final rows = await PackResultsDb.rowsForPack(lanPackUuid);
      expect(rows.single.clockFlags.last,
          {'type': 'clock_flags_overflow', 'dropped': 5});
      expect(
          OfflinePackSession.current!.chainUsage!.bytes, await exportBytes());
    });
  });

  // ── N-3 / N-6 (HubState) ───────────────────────────────────────────────────

  group('N-3 seat conflicts and N-6 re-join', () {
    late int t;
    late HubState st;

    setUp(() {
      t = 1000000;
      final pack = lanTestPack(extraStudents: 10);
      st = HubState(
        packUuid: lanPackUuid,
        schoolId: lanSchool,
        schoolCode: '999',
        hubName: 'h',
        groups: pack.groups,
        students: pack.students,
        allowedTestKeys: const ['t_all'],
        ticks: () => t,
      );
    });
    tearDown(() => st.dispose());

    HubClient joinAs(String ip, String machine) => st
        .join(ip: ip, code: st.code, machineId: machine, deviceName: machine)
        .client!;
    PingInput pi(String session, {String student = lanS1}) =>
        PingInput.fromJson({
          'session_id': session,
          'test_key': 't_all',
          'student_code': student,
          'name': 'n',
          'status': 'active'
        });

    test('one address holds at most 4 open conflicts; honest ones stay visible',
        () {
      final holder = joinAs('10.0.0.1', 'holder');
      st.ping(holder, pi('H1'));
      final atk = [for (var k = 0; k < 8; k++) joinAs('10.9.9.9', 'atk$k')];
      for (final a in atk) {
        expect(st.ping(a, pi('A-${a.id}'))['conflict'], true);
      }
      expect(st.conflicts(), hasLength(HubLimits.maxOpenConflictsPerIp));
      final honest = joinAs('10.0.0.7', 'honest');
      expect(st.ping(honest, pi('G1'))['conflict'], true);
      expect(st.conflicts().any((c) => c.claimant.ip == '10.0.0.7'), isTrue);
      expect(st.conflicts(), hasLength(HubLimits.maxOpenConflictsPerIp + 1));
    });

    test(
        'a freed seat goes to the claimant the teacher chose, not to the '
        'squatter\'s second token (reviewer\'s zz8)', () {
      final att1 = joinAs('10.0.0.99', 'att1');
      final att2 = joinAs('10.0.0.99', 'att2');
      final honest = joinAs('10.0.0.7', 'honest');
      st.ping(att1, pi('a1')); // squats the seat
      expect(st.ping(honest, pi('h1'))['conflict'], true);
      final c = st.conflicts().single;
      expect(c.claimant.deviceName, 'honest');
      st.resolveConflict(c.id, releaseHolder: true);

      // the attacker's other token pings FIRST: it must not win the seat
      expect(st.ping(att2, pi('a2'))['conflict'], true);
      expect(st.conflicts(), isEmpty,
          reason: 'no new banner for the blocked PC');
      expect(st.ping(att1, pi('a1'))['terminated'], true);
      // ...and the chosen claimant does
      expect(st.ping(honest, pi('h1'))['conflict'], false);
      expect(st.views().firstWhere((v) => v.inTest).id, honest.id);
    });

    test(
        'the reservation follows the claimant across its own re-join and '
        'expires after a minute', () {
      final att1 = joinAs('10.0.0.99', 'att1');
      final att2 = joinAs('10.0.0.99', 'att2');
      final honest = joinAs('10.0.0.7', 'honest');
      st.ping(att1, pi('a1'));
      st.ping(honest, pi('h1'));
      st.resolveConflict(st.conflicts().single.id, releaseHolder: true);

      final honest2 = joinAs('10.0.0.7', 'honest'); // app restarted: new token
      expect(st.ping(att2, pi('a2'))['conflict'], true);
      expect(st.ping(honest2, pi('h2'))['conflict'], false);
      st.kick(honest2.id);

      // a reservation nobody uses runs out
      final att3 = joinAs('10.0.0.99', 'att3');
      final other = joinAs('10.0.0.8', 'other');
      st.ping(att3, pi('a3', student: lanS2));
      st.ping(other, pi('o1', student: lanS2));
      st.resolveConflict(st.conflicts().single.id, releaseHolder: true);
      final late = joinAs('10.0.0.99', 'late');
      expect(st.ping(late, pi('l1', student: lanS2))['conflict'], true);
      t += HubLimits.seatReserveMs + 1;
      expect(st.ping(late, pi('l1', student: lanS2))['conflict'], false);
    });

    test('the banner carries device, address, connected-for and state', () {
      final holder = joinAs('10.0.0.1', 'pc-a');
      t += 5000;
      final claimant = joinAs('10.0.0.2', 'pc-b');
      st.ping(holder, pi('H1'));
      t += 7000;
      st.ping(claimant, pi('C1'));
      final c = st.conflicts().single;
      expect(c.studentName, 'Valiyev Ali');
      expect(c.holder.deviceName, 'pc-a');
      expect(c.holder.ip, '10.0.0.1');
      expect(c.holder.connectedAgoMs, 12000);
      expect(c.holder.status, ClientStatus.testing);
      expect(c.claimant.deviceName, 'pc-b');
      expect(c.claimant.connectedAgoMs, 7000);
      expect(c.claimant.status, ClientStatus.waiting);
    });

    test(
        'N-6: a re-join keeps the teacher\'s pause and the extra time already '
        'granted (and the terminated attempt)', () {
      final c = joinAs('10.0.0.5', 'mA');
      st.ping(c, pi('S1'));
      st.terminate(c.id);
      st.setLocked(c.id, true);
      st.addExtraTime(c.id, 300);

      final c2 = joinAs('10.0.0.5', 'mA');
      expect(c2.inTest, isTrue);
      expect(c2.locked, isTrue);
      expect(c2.extraTimeSeconds, 300);
      expect(c2.terminatedSessions, contains('S1'));
      final reply = st.ping(c2, pi('S1'));
      expect(reply['locked'], true);
      expect(reply['extra_time_seconds'], 300);
      expect(reply['terminated'], true);

      // a NEW attempt id starts clean, as before
      st.ping(c2, pi('S2'));
      expect(c2.locked, isFalse);
      expect(c2.extraTimeSeconds, 0);
    });
  });
}
