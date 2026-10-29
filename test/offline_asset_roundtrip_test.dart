// Round trip for the built-in ("assets") runners (decision 3): the REAL result
// screens -> pack chain (USB) / hub (LAN) -> ONE `.alochires` -> the BACKEND's
// own reader (verify_alochires.py) must open it and verify the HMAC chain keyed
// from the pack PIN. Same golden pack/keys as the other exporter tests.
//
// Needs python3 with `cryptography` and the backend checkout
// (ALOCHI_BACKEND_DIR -> alochi_backend/); skips loudly when either is missing.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/db/queue_crypto.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/asset_test_keys.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_asset_results.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/offline/results_exporter.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/features/interhouse/interhouse_data.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/asset_screens.dart';

const _fixtures = 'test/fixtures/offline';

/// Keys of the result screens runAllScreens pumps. The Unit1 / Combined /
/// Bob 1-4 / local-grade screens are gone, but their `asset:` keys stay in
/// kAssetTestKeys (results queued by older app versions must still be admitted).
const _exercisedKeys = {kAssetKeyInterhouse};

const _defaultBackend =
    '/Users/max/PycharmProjects/AlochiSchool/alochi/.claude/worktrees/agent-ab638607e6e37ee92/alochi_backend';

const _student = OfflineAssetStudent(
  studentId: '00000000-0000-4000-8000-0000000000d4',
  groupId: '00000000-0000-4000-8000-0000000000c3',
  groupName: '5-A',
  firstName: 'Oquvchi',
  lastName: 'Golden',
);

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

String? _backendDir() {
  final dir = Platform.environment['ALOCHI_BACKEND_DIR'] ?? _defaultBackend;
  final script = File(p.join(
      dir, 'apps/monitoring/tests/fixtures/offline/verify_alochires.py'));
  return script.existsSync() ? dir : null;
}

bool _pythonHasCryptography() {
  try {
    return Process.runSync('python3', ['-I', '-c', 'import cryptography'])
            .exitCode ==
        0;
  } catch (_) {
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keys = OfflineKeys(
    signingPem: File('$_fixtures/test_signing_public.pem').readAsStringSync(),
    resultsPem: File('$_fixtures/test_results_public.pem').readAsStringSync(),
  );
  final backend = _backendDir();
  final canVerify = backend != null && _pythonHasCryptography();
  final skipReason = canVerify
      ? null
      : 'python3+cryptography and the backend checkout (ALOCHI_BACKEND_DIR) are required';

  late Directory tmp;
  late LoadedPack pack;
  late IhTestData ih;

  setUpAll(() async {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pack = await PackLoader(keys: keys).open(
        File('$_fixtures/golden.alochipack').readAsBytesSync(), '12345678');
    ih = await IhLoader.load();
    // QueueCrypto caches its key FUTURE statically; created for the first time
    // inside a widget test's fake-async zone it would never complete.
    await QueueCrypto.encryptPayload('warm-up');
  });

  setUp(() async {
    await TestWidgetsFlutterBinding.instance.runAsync(() async {
      tmp = Directory.systemTemp.createTempSync('asset_rt_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    });
  });

  tearDown(() async {
    await TestWidgetsFlutterBinding.instance.runAsync(() async {
      OfflinePackSession.close();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });
  });

  /// Pumps the remaining real result screens one after the other and waits until
  /// each one's result is stored in the chain.
  Future<void> runAllScreens(WidgetTester t) async {
    final builders = <Widget Function()>[
      () => interhouseResult(_student, ih),
    ];
    for (var i = 0; i < builders.length; i++) {
      await t.pumpWidget(assetTestApp(builders[i]()));
      for (var k = 0; k < 150; k++) {
        final n =
            (await t.runAsync(() => PackResultsDb.rowsForPack(pack.packUuid)))!
                .length;
        if (n > i) break;
        await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)));
        await t.pump();
      }
      await t.pumpWidget(const SizedBox()); // leave the screen
    }
  }

  Future<void> exportAndVerify(WidgetTester t) async {
    final rows =
        (await t.runAsync(() => PackResultsDb.rowsForPack(pack.packUuid)))!;
    expect(rows, hasLength(_exercisedKeys.length));

    final out = (await t.runAsync(() => ResultsExporter(
          keys: keys,
          clock: MonitoredClock(
              ticks: () => 123456789,
              wall: () =>
                  DateTime.utc(2026, 10, 17, 9, 30, 15).millisecondsSinceEpoch,
              highWaterStore: _MemHwm()),
          machineId: () async => 'TEACHER-PC',
          mac: () async => 'AA:BB:CC:DD:EE:FF',
        ).exportPack(pack.packUuid, tmp, schoolCode: '999')))!;
    expect(out.count, _exercisedKeys.length);

    final args = [
      '-I',
      p.join(backend!,
          'apps/monitoring/tests/fixtures/offline/verify_alochires.py'),
      out.file.path,
      p.join(backend,
          'apps/monitoring/tests/fixtures/offline/test_results_private.pem'),
      '12345678',
      '--pack',
      '$_fixtures/golden.alochipack',
    ];
    final r = (await t.runAsync(() => Process.run('python3', args)))!;
    // ignore: avoid_print
    print('python3 ${args.join(' ')}\nexit=${r.exitCode}');
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    // ignore: avoid_print
    print('chain_verified=${j['chain_verified']} '
        'count=${(j['meta'] as Map)['count']} '
        'keys=${[
      for (final e in j['entries'] as List) (e['payload'] as Map)['test_key']
    ]}');
    expect(j['chain_verified'], true);
    expect((j['meta'] as Map)['count'], _exercisedKeys.length);

    final entries = (j['entries'] as List).cast<Map<String, dynamic>>();
    expect(entries.map((e) => (e['payload'] as Map)['test_key']).toSet(),
        _exercisedKeys);
    for (final e in entries) {
      final payload = e['payload'] as Map;
      expect(payload['student_id'], _student.studentId);
      expect(payload['group_id'], _student.groupId);
      expect(payload['school_code'], '999');
      expect((payload['detail'] as Map)['test_key'], payload['test_key']);
      // The shape the online /result/ body has: scores + name + variant.
      expect(payload['source'], 'flutter');
      expect(payload.containsKey('pct'), isTrue);
      expect(payload['variant'], isA<String>());
    }
    expect(entries.map((e) => e['idempotency_key']).toSet(), hasLength(_exercisedKeys.length));
  }

  testWidgets('USB: assets runners -> pack chain -> .alochires verifies',
      (tester) async {
    await tester.runAsync(() =>
        OfflinePackSession.open(pack, Directory(p.join(tmp.path, 'media'))));
    await runAllScreens(tester);
    expect(await tester.runAsync(OfflineQueue.pendingLocalCount), 0);
    await exportAndVerify(tester);
  }, skip: skipReason != null);

  testWidgets('LAN: assets runners -> hub -> chain -> .alochires verifies',
      (tester) async {
    late ShelfHub hub;
    late LanClientSession lan;
    final teacher = (await tester.runAsync(() async {
      final s = await OfflinePackSession.open(
          pack, Directory(p.join(tmp.path, 'media')));
      hub = ShelfHub(s,
          bindAddress: InternetAddress.loopbackIPv4,
          firstPort: 0,
          lastPort: 0,
          clock: MonitoredClock(
              ticks: () => 1000000, wall: () => 0, highWaterStore: _MemHwm()));
      await hub.start(announce: false);
      lan = await LanClientSession.join(
        host: '127.0.0.1',
        port: hub.port!,
        code: hub.state!.code,
        client: http.Client(),
        machineId: 'pc-1',
        deviceName: 'pc-1',
        mediaDirFor: (id) async => Directory(p.join(tmp.path, 'cm')),
      );
      return s;
    }))!;

    // From here on this process plays a student PC: a LAN session, no pack.
    OfflinePackSession.current = null;
    LanClientSession.current = lan;
    try {
      expect(offlineContentSource, same(lan));
      await runAllScreens(tester);
    } finally {
      LanClientSession.current = null;
      OfflinePackSession.current = teacher;
    }
    expect(hub.state!.resultsAccepted, _exercisedKeys.length);
    expect(await tester.runAsync(OfflineQueue.pendingLocalCount), 0);
    await exportAndVerify(tester);

    await tester.runAsync(() async {
      lan.close();
      await hub.stop();
      hub.dispose();
    });
  }, skip: skipReason != null);
}
