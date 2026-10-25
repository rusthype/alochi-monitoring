// writeLatest (safety backup), re-export of already-exported rows, and the
// flash-drive copy flow with fake drives.
import 'dart:io';
import 'dart:typed_data';

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

class _CountingExporter extends ResultsExporter {
  _CountingExporter(ResultsExporter base)
      : super(
            keys: base.keys,
            clock: base.clock,
            machineId: base.machineId,
            mac: base.mac);
  int builds = 0;
  int lastCount = 0;
  @override
  Future<
      ({
        Uint8List bytes,
        int count,
        String chainTip,
        int maxId,
        int invalidKeyCount
      })> build(String packUuid) async {
    builds++;
    final r = await super.build(packUuid);
    lastCount = r.count;
    return r;
  }
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
      await autoSaveLatest(pack.packUuid, '1',
          exporter: ResultsExporter(
              keys: const OfflineKeys(signingPem: '', resultsPem: '')),
          baseDir: () async => tmp);
      // Failed build: no backup file anywhere.
      expect(
          tmp
              .listSync(recursive: true)
              .where((e) => p.basename(e.path) == 'latest.alochires'),
          isEmpty);
    });

    test('autoSaveLatest coalesces a burst into few builds', () async {
      for (var i = 0; i < 20; i++) {
        await add('r$i');
      }
      final e = _CountingExporter(exporter());
      await Future.wait([
        for (var i = 0; i < 20; i++)
          autoSaveLatest(pack.packUuid, '1',
              exporter: e, baseDir: () async => tmp)
      ]);
      expect(e.builds, lessThanOrEqualTo(2));
      final f = File(p.join(
          (await packExportDir(tmp, pack.packUuid, schoolCode: '1')).path,
          'latest.alochires'));
      expect(f.existsSync(), isTrue);
      expect(e.lastCount, 20);
    });

    test('failed rename leaves the old file and no .tmp', () async {
      await add('a');
      final dir = Directory(p.join(tmp.path, 'bk'))..createSync();
      // A directory squatting on the target makes rename fail.
      Directory(p.join(dir.path, 'latest.alochires')).createSync();
      await expectLater(
          exporter().writeLatest(pack.packUuid, dir), throwsA(anything));
      expect(
          File(p.join(dir.path, 'latest.alochires.tmp')).existsSync(), isFalse);
    });
  });


  test('export name is <date>_<first 8 of uuid> in <maktab>_<tur>_<date>',
      () async {
    await add('a');
    final out =
        await exporter().exportPack(pack.packUuid, tmp, schoolCode: '9');
    expect(p.basename(out.file.path),
        endsWith('_${pack.packUuid.replaceAll('-', '').substring(0, 8)}.alochires'));
    expect(p.dirname(out.file.path), startsWith(p.join(tmp.path, '9-maktab_unknown_')));
  });

  test('same-second exports with colliding 8-char prefixes both survive',
      () async {
    const a = 'abcdefgh-0001-aaaa', b = 'abcdefgh-0002-bbbb';
    for (final u in [a, b]) {
      await PackResultsDb.append(
          packUuid: u,
          chainKey: Uint8List(32),
          idempotencyKey: 'k',
          payloadJson: '{"x":1}',
          incidents: const [],
          clockFlags: const []);
    }
    final e = exporter(); // frozen clock: identical timestamp
    final fa = (await e.exportPack(a, tmp)).file;
    final fb = (await e.exportPack(b, tmp)).file;
    expect(fa.path, isNot(fb.path));
    expect(fa.existsSync() && fb.existsSync(), isTrue);
  });

  test('exportPack never overwrites an existing file', () async {
    await add('a');
    final e = exporter();
    final first = (await e.exportPack(pack.packUuid, tmp)).file;
    first.writeAsStringSync('keep');
    final second = (await e.exportPack(pack.packUuid, tmp)).file;
    final third = (await e.exportPack(pack.packUuid, tmp)).file;
    expect(first.readAsStringSync(), 'keep');
    expect(p.basename(second.path), endsWith('-2.alochires'));
    expect(p.basename(third.path), endsWith('-3.alochires'));
  });

  group('AutoSaveStatus', () {
    setUp(() => AutoSaveStatus.all.value = const {});

    test('no entry before any run (e.g. after restart) = unknown, not failed',
        () {
      expect(AutoSaveStatus.all.value[pack.packUuid], isNull);
    });

    test('failure sets error state and never throws', () async {
      await add('a');
      await autoSaveLatest(pack.packUuid, '1',
          exporter: ResultsExporter(
              keys: const OfflineKeys(signingPem: '', resultsPem: '')),
          baseDir: () async => tmp);
      final e = AutoSaveStatus.all.value[pack.packUuid]!;
      expect(e.failed, isTrue);
      expect(e.lastOkAt, isNull);
    });

    test('success records time and count, and clears an earlier error',
        () async {
      await add('a');
      AutoSaveStatus.fail(pack.packUuid);
      await autoSaveLatest(pack.packUuid, '1',
          exporter: exporter(), baseDir: () async => tmp);
      final e = AutoSaveStatus.all.value[pack.packUuid]!;
      expect(e.failed, isFalse);
      expect(e.lastResultCount, 1);
      expect(e.lastOkAt, isNotNull);
    });
  });

  test('a row appended after the snapshot stays unexported', () async {
    await add('a');
    final e = exporter();
    final built = await e.build(pack.packUuid);
    await add('late'); // arrives between snapshot and stamp
    await PackResultsDb.markExported(pack.packUuid, 5, built.maxId);
    expect(await PackResultsDb.unexportedCount(pack.packUuid), 1);
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
            exports: [() async => exported],
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

    test('ExportException propagates, not mapped to failed', () async {
      await expectLater(
          exportToFlash(exports: [
            () async => throw const ExportException(ExportError.notConfigured)
          ], drives: () async => [drive.path], pick: (d) async => d.first),
          throwsA(isA<ExportException>()));
    });

    test('later pack failing still reports the packs already copied', () async {
      final second = File(p.join(tmp.path, 'y.alochires'))
        ..writeAsBytesSync(List.filled(500, 3));
      var n = 0;
      final r = await exportToFlash(
          exports: [() async => exported, () async => second],
          drives: () async => [drive.path],
          pick: (d) async => d.first,
          copier: (src, dst) async {
            if (++n == 2) throw const FileSystemException('boom');
            await src.copy(dst.path);
          });
      expect(r.status, FlashStatus.failed);
      expect(r.paths, hasLength(1));
      expect(File(r.paths.single).existsSync(), isTrue);
    });

    test('no drive -> noDrive and export is not run', () async {
      var exports = 0;
      final r = await exportToFlash(exports: [
        () async {
          exports++;
          return exported;
        }
      ], drives: () async => const [], pick: (_) async => null);
      expect(r.status, FlashStatus.noDrive);
      expect(exports, 0);
    });
  });
}
