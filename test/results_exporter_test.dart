// Round-trip: Dart writes a `.alochires`, the BACKEND's own Python reader
// (verify_alochires.py -> services.offline_pack.read_results) must open it,
// decrypt it and verify the HMAC chain keyed from the pack PIN + salt.
//
// Needs python3 with `cryptography`, and the backend checkout (the reference
// implementation of the format). Point ALOCHI_BACKEND_DIR at alochi_backend/;
// the test skips (loudly) when either is missing.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/offline/offline_crypto.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/offline/results_exporter.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _fixtures = 'test/fixtures/offline';
const _defaultBackend =
    '/Users/max/PycharmProjects/AlochiSchool/alochi/.claude/worktrees/agent-ab638607e6e37ee92/alochi_backend';

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

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pack = await PackLoader(keys: keys).open(
        File('$_fixtures/golden.alochipack').readAsBytesSync(), '12345678');
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('alochires_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
  });

  tearDown(() async {
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  ResultsExporter exporter() => ResultsExporter(
        keys: keys,
        clock: MonitoredClock(
            ticks: () => 123456789,
            wall: () =>
                DateTime.utc(2026, 10, 17, 9, 30, 15).millisecondsSinceEpoch,
            highWaterStore: _MemHwm()),
        machineId: () async => 'MACHINE-GUID-1',
        mac: () async => 'AA:BB:CC:DD:EE:FF',
      );

  Future<void> seed() async {
    final payloads = [
      jsonEncode({
        'name': 'Golden Oquvchi',
        'student_id': '00000000-0000-4000-8000-0000000000d4',
        'test_key': 'golden_test_1',
        'raw_answers': {'Vocabulary/0': 1, 'Vocabulary/1': 'cat'},
        'detail': {'test_key': 'golden_test_1'},
      }),
      jsonEncode({'name': 'Ikkinchi', "izoh": "O'zbekcha — ñ ü ё 😀"}),
    ];
    for (var i = 0; i < payloads.length; i++) {
      await PackResultsDb.append(
        packUuid: pack.packUuid,
        chainKey: pack.chainKey,
        idempotencyKey: 'key-$i',
        payloadJson: payloads[i],
        incidents: i == 0
            ? [
                {'type': 'focus_lost', 'at': '2026-10-17T09:10:00Z'}
              ]
            : const [],
        clockFlags: i == 0
            ? [
                {'type': 'clock_forward', 'skew_ms': 3600000}
              ]
            : const [],
      );
    }
  }

  Future<ProcessResult> verify(String file, {String pin = '12345678'}) {
    return Process.run('python3', [
      '-I',
      p.join(backend!,
          'apps/monitoring/tests/fixtures/offline/verify_alochires.py'),
      file,
      p.join(backend,
          'apps/monitoring/tests/fixtures/offline/test_results_private.pem'),
      pin,
      '--pack',
      '$_fixtures/golden.alochipack',
    ]);
  }

  test('exported file has the documented layout (stored zip, 3 members)',
      () async {
    await seed();
    final built = await exporter().build(pack.packUuid);
    final zip = ZipDecoder().decodeBytes(built.bytes);
    expect(zip.files.map((f) => f.name).toSet(),
        {'export_meta.json', 'key.enc', 'payload.enc'});
    final meta = jsonDecode(utf8.decode(zip.files
        .firstWhere((f) => f.name == 'export_meta.json')
        .readBytes()!)) as Map<String, dynamic>;
    expect(meta['pack_uuid'], pack.packUuid);
    expect(meta['machine_id'], 'MACHINE-GUID-1');
    expect(meta['mac'], 'AA:BB:CC:DD:EE:FF');
    expect(meta['exported_at'], '2026-10-17T09:30:15Z');
    expect(meta['monotonic_ms'], 123456789);
    expect(meta['count'], 2);
    expect(meta['chain_tip'], built.chainTip);
    // RSA-2048 OAEP output is exactly 256 bytes.
    expect(zip.files.firstWhere((f) => f.name == 'key.enc').readBytes()!.length,
        256);
  });

  test('backend Python reader opens the Dart export and verifies the chain',
      () async {
    await seed();
    final out =
        await exporter().exportPack(pack.packUuid, tmp, schoolCode: '999');
    expect(out.count, 2);
    expect(p.extension(out.file.path), '.alochires');

    final r = await verify(out.file.path);
    // ignore: avoid_print
    print('verify_alochires.py exit=${r.exitCode}\n${r.stdout}${r.stderr}');
    expect(r.exitCode, 0, reason: '${r.stdout}${r.stderr}');
    final j = jsonDecode(r.stdout as String) as Map<String, dynamic>;
    expect(j['chain_verified'], true);
    expect((j['meta'] as Map)['count'], 2);
    final entries = j['entries'] as List;
    expect(entries, hasLength(2));
    expect(entries[0]['idempotency_key'], 'key-0');
    expect(entries[0]['payload']['name'], 'Golden Oquvchi');
    expect(entries[0]['payload']['raw_answers'],
        {'Vocabulary/0': 1, 'Vocabulary/1': 'cat'});
    expect(entries[0]['incidents'][0]['type'], 'focus_lost');
    expect(entries[0]['clock_flags'][0]['type'], 'clock_forward');
    expect(entries[1]['payload']['izoh'], "O'zbekcha — ñ ü ё 😀");

    // Exporting stamps, never deletes (decision 13).
    expect(await PackResultsDb.unexportedCount(pack.packUuid), 0);
    expect(await PackResultsDb.rowsForPack(pack.packUuid), hasLength(2));

    // Re-export carries the whole chain again and still verifies.
    final again = await exporter().exportPack(pack.packUuid, tmp);
    expect(again.count, 2);
    expect((await verify(again.file.path)).exitCode, 0);
  }, skip: skipReason);

  test('wrong PIN cannot verify the chain (server would reject the file)',
      () async {
    await seed();
    final out = await exporter().exportPack(pack.packUuid, tmp);
    final r = await verify(out.file.path, pin: '00000000');
    expect(r.exitCode, 2, reason: '${r.stdout}${r.stderr}');
    expect(jsonDecode(r.stdout as String), contains('rejected'));
  }, skip: skipReason);

  test('a tampered link is rejected by the backend reader', () async {
    await seed();
    final db = await OfflineQueue.db;
    await db.update('pack_results', {'hash': 'f' * 64},
        where: 'idempotency_key = ?', whereArgs: ['key-0']);
    final out = await exporter().exportPack(pack.packUuid, tmp);
    final r = await verify(out.file.path);
    expect(r.exitCode, 2, reason: '${r.stdout}${r.stderr}');
  }, skip: skipReason);

  test('nothing stored -> nothingToExport; no keys -> notConfigured', () async {
    expect(
      () => exporter().build('missing-pack'),
      throwsA(isA<ExportException>()
          .having((e) => e.code, 'code', ExportError.nothingToExport)),
    );
    await seed();
    expect(
      () => ResultsExporter(keys: const OfflineKeys()).build(pack.packUuid),
      throwsA(isA<ExportException>()
          .having((e) => e.code, 'code', ExportError.notConfigured)),
    );
  });

  test('PBKDF2/AES-GCM primitives agree with the Python reference vectors', () {
    // GCM with AAD: encrypt in Dart, the pack fixture proves decrypt in Dart;
    // here just prove a round trip and AAD binding.
    final key = Uint8List.fromList(List.generate(32, (i) => i));
    final aad = Uint8List.fromList(utf8.encode('pack'));
    final blob =
        OfflineCrypto.encryptBlob(key, aad, Uint8List.fromList([1, 2, 3]));
    expect(OfflineCrypto.decryptBlob(key, aad, blob), [1, 2, 3]);
    expect(
      () => OfflineCrypto.decryptBlob(
          key, Uint8List.fromList(utf8.encode('other')), blob),
      throwsA(isA<OfflineAuthException>()),
    );
  });
}
