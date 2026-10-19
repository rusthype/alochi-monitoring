// Regression: the offline result token was `mw-<testKey>-<studentId>-<attempt>`
// (137 chars for a real combined test key) and the server rejects a whole
// `.alochires` when any meta idempotency_key is empty or > 64 (`bad_meta_json`).
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/lan_outbox_db.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_crypto.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/results_exporter.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/features/test/engine_host_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/lan_test_pack.dart';

const _longKey = 'cw1_b1-2-3-4-5-6-7-8_u1-2-3-4-5-6-7-8-9-10-11-12_s2028115031';
const _student = 'b265df9d-da8f-4364-96e0-52e105d9e2f0';
const _attempt = 'ba917162-990d-4154-a6a8-195947fbeda3';
// The exact old-format token the real PC stored.
const _oldToken = 'mw-$_longKey-$_student-$_attempt';

/// Dart mirror of the server's `_parse_entry_meta` checks.
void expectServerAcceptsMeta(String metaJson) {
  final m = jsonDecode(metaJson) as Map<String, dynamic>;
  final k = m['idempotency_key'];
  expect(k, isA<String>());
  expect((k as String).length, inInclusiveRange(1, 64), reason: 'key=$k');
  expect(m['incidents'], isA<List>());
  expect(m['clock_flags'], isA<List>());
}

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

Future<void> eventually(Future<bool> Function() cond) async {
  final end = DateTime.now().add(const Duration(seconds: 8));
  while (!await cond()) {
    if (DateTime.now().isAfter(end)) fail('condition not met in time');
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('root cause: the old format really was > 64 chars', () {
    expect(_oldToken.length, greaterThan(64));
  });

  group('buildResultToken', () {
    final t = buildResultToken(_longKey, _student, _attempt);

    test('fits the server rule, even for a very long test key', () {
      expect(t.length, inInclusiveRange(1, 64));
      expect(RegExp(r'^[A-Za-z0-9:_.\-]+$').hasMatch(t), isTrue);
      expect(
        buildResultToken('x' * 500, _student, _attempt).length,
        lessThanOrEqualTo(64),
      );
    });

    test('deterministic for the same attempt, unique otherwise', () {
      expect(buildResultToken(_longKey, _student, _attempt), t);
      expect(buildResultToken(_longKey, _student, 'other'), isNot(t));
      expect(buildResultToken(_longKey, 'other', _attempt), isNot(t));
      expect(buildResultToken('${_longKey}2', _student, _attempt), isNot(t));
    });
  });

  group('USB pack', () {
    late Directory tmp;
    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('idem64_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    });
    tearDown(() async {
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    test(
      'append hashes an over-long key; meta passes the server rule',
      () async {
        final chainKey = OfflineCrypto.randomBytes(32);
        final r1 = await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: chainKey,
          idempotencyKey: _oldToken,
          payloadJson: '{"a":1}',
        );
        expectServerAcceptsMeta(r1.metaJson);
        expect(r1.idempotencyKey, startsWith('h:'));
        // Same input again dedupes onto the same hashed row.
        final r2 = await PackResultsDb.append(
          packUuid: 'pk',
          chainKey: chainKey,
          idempotencyKey: _oldToken,
          payloadJson: '{"a":1}',
        );
        expect(r2.id, r1.id);
        expect(await PackResultsDb.hasKey('pk', _oldToken), isTrue);
        expect((await PackResultsDb.rowsForPack('pk')).length, 1);
      },
    );

    test('a legacy stored long-key row is reported by the exporter', () async {
      final d = await OfflineQueue.db;
      await d.insert('pack_results', {
        'pack_uuid': 'pk',
        'idempotency_key': _oldToken,
        'payload': await QueueCrypto.encryptPayload('{"a":1}'),
        'meta_json': PackResultsDb.metaJsonFor(_oldToken, [], []),
        'prev_hash': OfflineCrypto.zeroHash,
        'hash': 'h' * 64,
        'created': 1,
      });
      final keys = OfflineKeys(
        signingPem: File(
          'test/fixtures/offline/test_signing_public.pem',
        ).readAsStringSync(),
        resultsPem: File(
          'test/fixtures/offline/test_results_public.pem',
        ).readAsStringSync(),
      );
      final built = await ResultsExporter(
        keys: keys,
        clock: MonitoredClock(
          ticks: () => 1,
          wall: () => 0,
          highWaterStore: _MemHwm(),
        ),
        machineId: () async => 'm',
        mac: () async => 'a',
      ).build('pk');
      expect(built.invalidKeyCount, 1);
    });
  });

  group('LAN loopback', () {
    late Directory tmp;
    late ShelfHub hub;
    final sessions = <LanClientSession>[];

    setUp(() async {
      tmp = Directory.systemTemp.createTempSync('idem64lan_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      final clock = MonitoredClock(
        ticks: () => 1000000,
        wall: () => 0,
        highWaterStore: _MemHwm(),
      );
      final sha = OfflineCrypto.sha256Hex(lanMediaBytes);
      final session = await OfflinePackSession.open(
        lanTestPack(mediaRef: 'media/$sha.jpg'),
        makeMediaDir(tmp, sha),
      );
      hub = ShelfHub(
        session,
        bindAddress: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
        clock: clock,
      );
      await hub.start(announce: false);
    });
    tearDown(() async {
      for (final s in sessions) {
        s.close();
      }
      sessions.clear();
      await hub.stop();
      hub.dispose();
      OfflinePackSession.close();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });

    test('realistic token is accepted, counted once, resend dedupes', () async {
      final s = await LanClientSession.join(
        host: '127.0.0.1',
        port: hub.port!,
        code: hub.state!.code,
        client: http.Client(),
        machineId: 'pc-1',
        deviceName: 'PC',
        mediaDirFor: (id) async => Directory(p.join(tmp.path, 'cm', id)),
      );
      sessions.add(s);
      final token = buildResultToken(_longKey, _student, _attempt);
      for (var i = 0; i < 2; i++) {
        await s.recordResult(lanResultPayload(), token: token);
        await s.flushOutbox();
      }
      // The raw legacy long token is also tolerated (hashed).
      await s.recordResult(lanResultPayload(), token: _oldToken);
      await s.flushOutbox();

      await eventually(() async {
        await s.flushOutbox();
        return (await PackResultsDb.rowsForPack(lanPackUuid)).length == 2 &&
            (await LanOutboxDb.pending(lanPackUuid)).isEmpty;
      });
      final rows = await PackResultsDb.rowsForPack(lanPackUuid);
      expect(rows.length, 2);
      for (final r in rows) {
        expectServerAcceptsMeta(r.metaJson);
      }
      expect(rows.first.idempotencyKey, token);
      expect(hub.state!.refusedResults, 0);
      expect(await LanOutboxDb.pending(lanPackUuid), isEmpty);
    });
  });
}
