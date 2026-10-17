// Phase 3 round trip: three student PCs -> hub -> ONE `.alochires` -> the
// BACKEND's own reader (verify_alochires.py) must open it and verify the HMAC
// chain keyed from the pack PIN. Same golden pack/keys as the USB exporter test.
//
// Needs python3 with `cryptography` and the backend checkout
// (ALOCHI_BACKEND_DIR -> alochi_backend/); skips loudly when either is missing.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/local_server/shelf_hub.dart';
import 'package:alochi_monitoring/core/offline/lan_client_api.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/offline/results_exporter.dart';
import 'package:alochi_monitoring/core/security/incident_log.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _fixtures = 'test/fixtures/offline';
const _defaultBackend =
    '/Users/max/PycharmProjects/AlochiSchool/alochi/.claude/worktrees/agent-ab638607e6e37ee92/alochi_backend';
const _student = '00000000-0000-4000-8000-0000000000d4';
const _group = '00000000-0000-4000-8000-0000000000c3';

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
  late ShelfHub hub;
  final sessions = <LanClientSession>[];

  setUpAll(() async {
    HttpOverrides.global = null;
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pack = await PackLoader(keys: keys).open(
        File('$_fixtures/golden.alochipack').readAsBytesSync(), '12345678');
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('lan_roundtrip_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    final session = await OfflinePackSession.open(
        pack, Directory(p.join(tmp.path, 'media')));
    hub = ShelfHub(session,
        bindAddress: InternetAddress.loopbackIPv4,
        firstPort: 0,
        lastPort: 0,
        clock: MonitoredClock(
            ticks: () => 1000000, wall: () => 0, highWaterStore: _MemHwm()));
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

  Future<LanClientSession> pc(String machine) async {
    final s = await LanClientSession.join(
      host: '127.0.0.1',
      port: hub.port!,
      code: hub.state!.code,
      client: http.Client(),
      machineId: machine,
      deviceName: machine,
      mediaDirFor: (id) async => Directory(p.join(tmp.path, 'cm', machine)),
    );
    sessions.add(s);
    return s;
  }

  test('3 PCs -> hub -> one .alochires -> backend reader verifies the chain',
      () async {
    final pcs = [await pc('pc-1'), await pc('pc-2'), await pc('pc-3')];
    for (var i = 0; i < pcs.length; i++) {
      IncidentLog.instance.add('focus_lost', {'pc': i});
      await LanClientApi(pcs[i]).submitLocalResultFull({
        'name': 'Golden Oquvchi',
        'grade': 5,
        'variant': '1',
        'source': 'flutter',
        'student_id': _student,
        'group_id': _group,
        'school_code': '999',
        'test_key': 'golden_test_1',
        'raw_answers': {'Vocabulary/0': i, 'Vocabulary/1': 'cat'},
        'detail': {'test_key': 'golden_test_1'},
        'izoh': "O'zbekcha — ñ ü ё",
      }, 'rt-key-$i');
      // Deliver this PC's outbox before the next result is made, so the chain
      // order is deterministic (pc-1, pc-2, pc-3).
      await pcs[i].flushOutbox();
      for (var k = 0;
          k < 100 &&
              (await PackResultsDb.rowsForPack(pack.packUuid)).length < i + 1;
          k++) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
    }
    final rows = await PackResultsDb.rowsForPack(pack.packUuid);
    expect(rows, hasLength(3));
    expect(hub.state!.resultsAccepted, 3);

    // Teacher exports ONCE.
    final out = await ResultsExporter(
      keys: keys,
      clock: MonitoredClock(
          ticks: () => 123456789,
          wall: () =>
              DateTime.utc(2026, 10, 17, 9, 30, 15).millisecondsSinceEpoch,
          highWaterStore: _MemHwm()),
      machineId: () async => 'TEACHER-PC',
      mac: () async => 'AA:BB:CC:DD:EE:FF',
    ).exportPack(pack.packUuid, tmp, schoolCode: '999');
    expect(out.count, 3);

    final r = await Process.run('python3', [
      '-I',
      p.join(backend!,
          'apps/monitoring/tests/fixtures/offline/verify_alochires.py'),
      out.file.path,
      p.join(backend,
          'apps/monitoring/tests/fixtures/offline/test_results_private.pem'),
      '12345678',
      '--pack',
      '$_fixtures/golden.alochipack',
    ]);
    // ignore: avoid_print
    print('verify_alochires.py exit=${r.exitCode}\n${r.stdout}${r.stderr}');
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    expect(j['chain_verified'], true);
    expect((j['meta'] as Map)['count'], 3);
    final entries = (j['entries'] as List).cast<Map<String, dynamic>>();
    expect(entries.map((e) => e['idempotency_key']),
        ['rt-key-0', 'rt-key-1', 'rt-key-2']);
    expect(entries.first['payload']['student_id'], _student);
    expect(entries.first['payload']['izoh'], "O'zbekcha — ñ ü ё");
    expect(entries[1]['payload']['raw_answers'],
        {'Vocabulary/0': 1, 'Vocabulary/1': 'cat'});
    expect(entries.map((e) => (e['incidents'] as List).last['machine_id']),
        ['pc-1', 'pc-2', 'pc-3']);
    // The incident each PC collected travelled with its own result.
    expect((entries[2]['incidents'] as List).first['pc'], 2);
  }, skip: skipReason);
}
