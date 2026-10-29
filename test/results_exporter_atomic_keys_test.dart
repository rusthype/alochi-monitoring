// F26: the export is written verified + atomically, and an entry with an
// invalid idempotency key is kept OUT of the file (valid prefix only) while
// staying in the local store.
import 'dart:convert';
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/offline/results_exporter.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const _fixtures = 'test/fixtures/offline';

class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final keys = OfflineKeys(
    signingPem: File('$_fixtures/test_signing_public.pem').readAsStringSync(),
    resultsPem: File('$_fixtures/test_results_public.pem').readAsStringSync(),
  );
  late Directory tmp;
  late LoadedPack pack;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    pack = await PackLoader(keys: keys).open(
        File('$_fixtures/golden.alochipack').readAsBytesSync(), '12345678');
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('alochires_atomic_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
  });

  tearDown(() async {
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  ResultsExporter exporter() => ResultsExporter(
        keys: keys,
        clock: MonitoredClock(
            ticks: () => 1, wall: () => 0, highWaterStore: _MemHwm()),
        machineId: () async => 'm',
        mac: () async => 'a',
      );

  Future<List<int>> seed(int n) async {
    final ids = <int>[];
    for (var i = 0; i < n; i++) {
      final r = await PackResultsDb.append(
        packUuid: pack.packUuid,
        chainKey: pack.chainKey,
        idempotencyKey: 'key-$i',
        payloadJson: jsonEncode({'name': 'S$i'}),
        incidents: const [],
        clockFlags: const [],
      );
      ids.add(r.id);
    }
    return ids;
  }

  /// Simulates a legacy row whose stored key became invalid.
  Future<void> breakKey(int id) async {
    final d = await OfflineQueue.db;
    await d.update('pack_results', {'idempotency_key': 'x' * 70},
        where: 'id = ?', whereArgs: [id]);
  }

  Map<String, dynamic> metaOf(File f) {
    final a = ZipDecoder().decodeBytes(f.readAsBytesSync());
    return jsonDecode(utf8.decode(a.findFile('export_meta.json')!.content))
        as Map<String, dynamic>;
  }

  test('export leaves exactly the .alochires, no temp file', () async {
    await seed(2);
    final out = await exporter().exportPack(pack.packUuid, tmp);
    expect(out.file.existsSync(), isTrue);
    expect(out.invalidKeyCount, 0);
    final all = out.file.parent.listSync().map((e) => p.basename(e.path));
    expect(all.where((n) => n.endsWith('.tmp')), isEmpty);
    expect(metaOf(out.file)['count'], 2);
  });

  test('a bad key in the middle: valid prefix exported, rest held back',
      () async {
    final ids = await seed(3);
    await breakKey(ids[1]);
    final rows = await PackResultsDb.rowsForPack(pack.packUuid);
    final out = await exporter().exportPack(pack.packUuid, tmp);
    expect(out.count, 1);
    expect(out.invalidKeyCount, 2);
    expect(out.chainTip, rows[0].hash);
    final m = metaOf(out.file);
    expect(m['count'], 1);
    expect(m['chain_tip'], rows[0].hash);
    // Nothing is dropped locally; only the exported prefix is stamped.
    expect((await PackResultsDb.rowsForPack(pack.packUuid)).length, 3);
    expect(await PackResultsDb.unexportedCount(pack.packUuid), 2);
  });

  test('first entry bad: legacy whole-chain file, still reported', () async {
    final ids = await seed(2);
    await breakKey(ids[0]);
    final out = await exporter().exportPack(pack.packUuid, tmp);
    expect(out.count, 2);
    expect(out.invalidKeyCount, 1);
  });

  test('writeLatest is verified too and leaves no temp', () async {
    await seed(1);
    final out = await exporter().writeLatest(pack.packUuid, tmp);
    expect(out.file.existsSync(), isTrue);
    expect(File('${out.file.path}.tmp').existsSync(), isFalse);
  });
}
