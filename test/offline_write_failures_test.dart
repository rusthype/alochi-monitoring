// Removed USB stick / full disk / read-only destination for every file-write
// path of the offline + diagnostic export flows. Each path must (1) throw a
// handled FileSystemException (never succeed silently), (2) leave no partial
// file under the FINAL name (and no .tmp), (3) never touch an existing good
// file, and (4) not stamp anything as exported.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/offline/atomic_file.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/offline/results_exporter.dart';
import 'package:alochi_monitoring/core/offline/usb_backup.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/core/services/diagnostic_export_service.dart';
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

/// ENOSPC as Dart reports it: POSIX errno 28, Windows ERROR_DISK_FULL 112.
FileSystemException _diskFull(String path, {int code = 28}) =>
    FileSystemException(
        'writeFrom failed', path, OSError('No space left on device', code));

/// chmod 555 [dir]; false when that does not actually block writes here
/// (Windows, or running as root) so the caller can skip.
Future<bool> _makeReadOnly(Directory dir) async {
  if (Platform.isWindows) return false;
  await Process.run('chmod', ['555', dir.path]);
  try {
    File(p.join(dir.path, '.probe')).writeAsBytesSync([1]);
    File(p.join(dir.path, '.probe')).deleteSync();
    await Process.run('chmod', ['755', dir.path]);
    return false;
  } on FileSystemException {
    return true;
  }
}

List<String> _names(Directory d) =>
    d.listSync().map((e) => p.basename(e.path)).toList()..sort();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final keys = OfflineKeys(
    signingPem: File('$_fixtures/test_signing_public.pem').readAsStringSync(),
    resultsPem: File('$_fixtures/test_results_public.pem').readAsStringSync(),
  );
  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('write_fail_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
  });

  tearDown(() async {
    if (!Platform.isWindows) {
      await Process.run('chmod', ['-R', '755', tmp.path]);
    }
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  final data = Uint8List.fromList(List.generate(5000, (i) => i % 251));

  group('writeFileVerified (shared by export, zip, media, LAN media)', () {
    for (final code in [28, 112]) {
      test('disk full (os error $code) mid-write: rethrown, nothing left',
          () async {
        final f = File(p.join(tmp.path, 'a.bin'));
        await expectLater(
            writeFileVerified(f, data, write: (t, b) async {
              await t.writeAsBytes(b.sublist(0, 100), flush: true);
              throw _diskFull(t.path, code: code);
            }),
            throwsA(isA<FileSystemException>()
                .having((e) => e.osError?.errorCode, 'errno', code)));
        expect(f.existsSync(), isFalse);
        expect(File('${f.path}.tmp').existsSync(), isFalse);
      });
    }

    test('disk full never truncates an existing good file', () async {
      final f = File(p.join(tmp.path, 'a.bin'))..writeAsBytesSync([1, 2, 3]);
      await expectLater(
          writeFileVerified(f, data, write: (t, b) async {
            await t.writeAsBytes(b.sublist(0, 10), flush: true);
            throw _diskFull(t.path);
          }),
          throwsA(isA<FileSystemException>()));
      expect(f.readAsBytesSync(), [1, 2, 3]);
      expect(File('${f.path}.tmp').existsSync(), isFalse);
    });

    test('stick pulled mid-write (directory gone): throws, not recreated',
        () async {
      final dir = Directory(p.join(tmp.path, 'E'))..createSync();
      final f = File(p.join(dir.path, 'a.bin'));
      await expectLater(
          writeFileVerified(f, data, write: (t, b) async {
            await t.writeAsBytes(b, flush: true);
            dir.deleteSync(recursive: true);
          }),
          throwsA(isA<FileSystemException>()));
      expect(dir.existsSync(), isFalse);
    });

    test('destination directory never existed: throws, creates nothing',
        () async {
      final f = File(p.join(tmp.path, 'gone', 'a.bin'));
      await expectLater(
          writeFileVerified(f, data), throwsA(isA<FileSystemException>()));
      expect(Directory(p.join(tmp.path, 'gone')).existsSync(), isFalse);
    });

    test(
        'rename fails (target is a non-empty directory): temp cleaned, '
        'target untouched', () async {
      final target = Directory(p.join(tmp.path, 'a.bin'))..createSync();
      File(p.join(target.path, 'keep')).writeAsBytesSync([7]);
      await expectLater(writeFileVerified(File(target.path), data),
          throwsA(isA<FileSystemException>()));
      expect(File('${target.path}.tmp').existsSync(), isFalse);
      expect(File(p.join(target.path, 'keep')).readAsBytesSync(), [7]);
    });

    test('read-only destination directory: throws, nothing written', () async {
      final dir = Directory(p.join(tmp.path, 'ro'))..createSync();
      if (!await _makeReadOnly(dir)) {
        markTestSkipped('chmod not effective here');
        return;
      }
      await expectLater(
          writeFileVerified(File(p.join(dir.path, 'a.bin')), data),
          throwsA(isA<FileSystemException>()));
      expect(_names(dir), isEmpty);
    });
  });

  group('saveZipUnique (diagnostic zip export)', () {
    final now = DateTime(2026, 11, 5, 9, 30, 15);

    test('destination gone: throws, so the screen shows the error, not saved',
        () async {
      final dir = Directory(p.join(tmp.path, 'Downloads'));
      await expectLater(DiagnosticExportService.saveZipUnique(dir, data, now),
          throwsA(isA<FileSystemException>()));
      expect(dir.existsSync(), isFalse);
    });

    test('read-only Downloads: throws, no zip and no temp', () async {
      final dir = Directory(p.join(tmp.path, 'ro'))..createSync();
      if (!await _makeReadOnly(dir)) {
        markTestSkipped('chmod not effective here');
        return;
      }
      await expectLater(DiagnosticExportService.saveZipUnique(dir, data, now),
          throwsA(isA<FileSystemException>()));
      expect(_names(dir), isEmpty);
    });

    test('an existing zip of the same second is never replaced', () async {
      final dir = Directory(p.join(tmp.path, 'd'))..createSync();
      final first = await DiagnosticExportService.saveZipUnique(dir, data, now);
      final second = await DiagnosticExportService.saveZipUnique(
          dir, Uint8List.fromList([1]), now);
      expect(second, isNot(first));
      expect(File(first).readAsBytesSync(), data);
    });
  });

  group('ResultsExporter (.alochires export + latest backup)', () {
    late LoadedPack pack;
    setUpAll(() async {
      pack = await PackLoader(keys: keys).open(
          File('$_fixtures/golden.alochipack').readAsBytesSync(), '12345678');
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
        );

    test('export into a read-only pack folder: throws, rows stay unexported',
        () async {
      await add('a');
      final folder = await packExportDir(tmp, pack.packUuid, schoolCode: '1');
      if (!await _makeReadOnly(folder)) {
        markTestSkipped('chmod not effective here');
        return;
      }
      await expectLater(
          exporter().exportPack(pack.packUuid, tmp, schoolCode: '1'),
          throwsA(isA<FileSystemException>()));
      expect(await PackResultsDb.unexportedCount(pack.packUuid), 1);
      expect(_names(folder).where((n) => n.endsWith('.alochires')), isEmpty);
      expect(_names(folder).where((n) => n.endsWith('.tmp')), isEmpty);
    });

    test('latest backup into a read-only folder keeps the previous backup',
        () async {
      await add('a');
      final dir = Directory(p.join(tmp.path, 'bk'));
      await exporter().writeLatest(pack.packUuid, dir);
      final latest = File(p.join(dir.path, 'latest.alochires'));
      final before = latest.readAsBytesSync();
      await add('b');
      if (!await _makeReadOnly(dir)) {
        markTestSkipped('chmod not effective here');
        return;
      }
      await expectLater(exporter().writeLatest(pack.packUuid, dir),
          throwsA(isA<FileSystemException>()));
      expect(latest.readAsBytesSync(), before);
      expect(_names(dir), ['latest.alochires']);
    });

    test('latest backup: autoSaveLatest reports the failure, never throws',
        () async {
      await add('a');
      final base = Directory(p.join(tmp.path, 'base'))..createSync();
      final folder = await packExportDir(base, pack.packUuid, schoolCode: '1');
      if (!await _makeReadOnly(folder)) {
        markTestSkipped('chmod not effective here');
        return;
      }
      await autoSaveLatest(pack.packUuid, '1',
          exporter: exporter(), baseDir: () async => base);
      expect(AutoSaveStatus.all.value[pack.packUuid]?.failed, isTrue);
      expect(_names(folder).where((n) => n == 'latest.alochires'), isEmpty);
    });
  });

  group('copyToFlash / exportToFlash (copy onto the USB stick)', () {
    late File src;
    late Directory drive;
    setUp(() {
      src = File(p.join(tmp.path, 'x.alochires'))
        ..writeAsBytesSync(List.filled(1000, 7));
      drive = Directory(p.join(tmp.path, 'E'))..createSync();
    });

    Future<FlashResult> run({
      required Future<void> Function(File, File) copier,
    }) =>
        exportToFlash(
            exports: [() async => src],
            drives: () async => [drive.path],
            pick: (d) async => d.first,
            copier: copier);

    File finalFile() =>
        File(p.join(drive.path, 'alochi-offline', 'x.alochires'));

    for (final code in [28, 112]) {
      test('disk full (os error $code) mid-copy: failed, no final file',
          () async {
        final r = await run(copier: (s, d) async {
          await d.writeAsBytes([1, 2, 3]);
          throw _diskFull(d.path, code: code);
        });
        expect(r.status, FlashStatus.failed);
        expect(r.paths, isEmpty);
        expect(finalFile().existsSync(), isFalse);
        expect(src.existsSync(), isTrue); // the Downloads copy is kept
      });
    }

    test('disk full never replaces a good copy already on the stick', () async {
      finalFile()
        ..createSync(recursive: true)
        ..writeAsBytesSync([9, 9, 9]);
      final r = await run(copier: (s, d) async {
        await d.writeAsBytes([1]);
        throw _diskFull(d.path);
      });
      expect(r.status, FlashStatus.failed);
      expect(finalFile().readAsBytesSync(), [9, 9, 9]);
    });

    test('stick pulled mid-copy (drive folder gone): failed, not "ok"',
        () async {
      final r = await run(copier: (s, d) async {
        drive.deleteSync(recursive: true);
        throw PathNotFoundException(d.path, const OSError('No such file', 2));
      });
      expect(r.status, FlashStatus.failed);
      expect(r.paths, isEmpty);
    });

    test('stick pulled after the copy, before the rename: failed, no final',
        () async {
      final r = await run(copier: (s, d) async {
        await s.copy(d.path);
        // The verification reads the .part back; remove the folder right
        // after the copy so the flush/verify/rename step has nothing to use.
        drive.deleteSync(recursive: true);
      });
      expect(r.status, FlashStatus.failed);
      expect(drive.existsSync(), isFalse);
    });

    test('read-only stick: failed, nothing written on it', () async {
      if (!await _makeReadOnly(drive)) {
        markTestSkipped('chmod not effective here');
        return;
      }
      final r = await run(copier: (s, d) => s.copy(d.path));
      expect(r.status, FlashStatus.failed);
      expect(_names(drive), isEmpty);
    });
  });

  group('reading from / unpacking onto disk', () {
    test('pack file on a pulled stick: inspectPackFile throws a handled error',
        () async {
      await expectLater(
          inspectPackFile(p.join(tmp.path, 'E', 'gone.alochipack'), keys,
              now: DateTime.utc(2026, 1, 1)),
          throwsA(anything));
    });

    test('media dir read-only: unlock throws, no media file appears', () async {
      final media = Directory(p.join(tmp.path, 'media'))..createSync();
      if (!await _makeReadOnly(media)) {
        markTestSkipped('chmod not effective here');
        return;
      }
      await expectLater(
          PackLoader(keys: keys).open(
              File('$_fixtures/golden.alochipack').readAsBytesSync(),
              '12345678',
              mediaDir: media),
          throwsA(isA<FileSystemException>()));
      expect(_names(media), isEmpty);
    });
  });
}
