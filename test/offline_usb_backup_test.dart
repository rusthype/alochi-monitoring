// writeLatest (safety backup), re-export of already-exported rows, and the
// flash-drive copy flow with fake drives.
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/offline/results_exporter.dart';
import 'package:alochi_monitoring/core/offline/usb_backup.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
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
    tmp = Directory.systemTemp.createTempSync('usb_backup_');
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
        machineId: () async => 'M',
        mac: () async => 'AA',
      );

  Future<void> add(String key) => PackResultsDb.append(
        packUuid: pack.packUuid,
        chainKey: pack.chainKey,
        idempotencyKey: key,
        payloadJson: '{"name":"$key"}',
        incidents: const [],
        clockFlags: const [],
      );

  group('writeLatest', () {
    test('atomic file, no exported_at stamp, no temp left', () async {
      await add('a');
      final dir = Directory(p.join(tmp.path, 'bk'));
      final out = await exporter().writeLatest(pack.packUuid, dir);
      expect(p.basename(out.file.path), 'latest.alochires');
      expect(out.count, 1);
      expect(await PackResultsDb.unexportedCount(pack.packUuid), 1);
      expect(
          dir.listSync().map((e) => p.basename(e.path)), ['latest.alochires']);

      await add('b');
      final out2 = await exporter().writeLatest(pack.packUuid, dir);
      expect(out2.count, 2);
      expect(dir.listSync(), hasLength(1));
    });

    test('concurrent calls are serialised and leave a valid file', () async {
      await add('a');
      final dir = Directory(p.join(tmp.path, 'bk'));
      final e = exporter();
      final outs = await Future.wait(
          [for (var i = 0; i < 5; i++) e.writeLatest(pack.packUuid, dir)]);
      expect(outs.every((o) => o.count == 1), isTrue);
      expect(dir.listSync(), hasLength(1));
      expect(File(p.join(dir.path, 'latest.alochires')).lengthSync(),
          greaterThan(0));
    });

    test('autoSaveLatest never throws (unconfigured keys)', () async {
      await add('a');
      autoSaveLatest(pack.packUuid, '1',
          exporter: ResultsExporter(
              keys: const OfflineKeys(signingPem: '', resultsPem: '')),
          baseDir: () async => tmp);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
  });

  test('global export still exports packs whose rows are all exported',
      () async {
    await add('a');
    await exporter().exportPack(pack.packUuid, tmp);
    final s = (await PackResultsDb.summaries()).single;
    expect(s.unexported, 0);
    expect(s.total, 1); // dialog filters on total > 0
    final again = await exporter().exportPack(s.packUuid, tmp);
    expect(again.count, 1);
  });

  group('exportToFlash', () {
    late File exported;
    late Directory drive;
    setUp(() {
      exported = File(p.join(tmp.path, 'x.alochires'))
        ..writeAsBytesSync(List.filled(1000, 7));
      drive = Directory(p.join(tmp.path, 'E'))..createSync();
    });

    Future<FlashResult> run(List<String> drives,
            {Future<void> Function(File, File)? copier}) =>
        exportToFlash(
            export: () async => exported,
            drives: () async => drives,
            pick: (d) async => d.last,
            copier: copier);

    test('one drive: copies and verifies', () async {
      final r = await run([drive.path]);
      expect(r.status, FlashStatus.ok);
      expect(File(r.path!).lengthSync(), 1000);
      expect(r.path, contains('alochi-offline'));
      expect(exported.existsSync(), isTrue);
    });

    test('several drives: asks the user to pick', () async {
      final other = Directory(p.join(tmp.path, 'F'))..createSync();
      final r = await run([drive.path, other.path]);
      expect(r.path, startsWith(other.path));
    });

    test('size mismatch -> failed, Downloads copy kept, no final file',
        () async {
      final r = await run([drive.path], copier: (src, dst) async {
        await dst.writeAsBytes([1, 2, 3]);
      });
      expect(r.status, FlashStatus.failed);
      expect(exported.existsSync(), isTrue);
      expect(
          File(p.join(drive.path, 'alochi-offline', 'x.alochires'))
              .existsSync(),
          isFalse);
    });

    test('no drive -> noDrive and export is not run', () async {
      var exports = 0;
      final r = await exportToFlash(
          export: () async {
            exports++;
            return exported;
          },
          drives: () async => const [],
          pick: (_) async => null);
      expect(r.status, FlashStatus.noDrive);
      expect(exports, 0);
    });
  });
}
