// Export layout per round (<maktab>_<tur>_<date>/<date>_<id8>) and
// the local archive flag on pack_meta.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/results_exporter.dart';
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

String _ymd(DateTime d) {
  final l = d.toLocal();
  String two(int v) => v.toString().padLeft(2, '0');
  return '${l.year}-${two(l.month)}-${two(l.day)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final keys = OfflineKeys(
    signingPem: File('$_fixtures/test_signing_public.pem').readAsStringSync(),
    resultsPem: File('$_fixtures/test_results_public.pem').readAsStringSync(),
  );
  final exportAt = DateTime.utc(2026, 10, 17, 9, 30, 15);
  final created = DateTime.utc(2026, 9, 26, 12);
  final expires = DateTime.utc(2027, 1, 1);
  const monUuid = 'aaaaaaaa-1111-4111-8111-000000000001';
  const diagUuid = 'bbbbbbbb-2222-4222-8222-000000000002';

  late Directory tmp;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('by_round_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
  });

  tearDown(() async {
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  ResultsExporter exporter() => ResultsExporter(
        keys: keys,
        clock: MonitoredClock(
            ticks: () => 1,
            wall: () => exportAt.millisecondsSinceEpoch,
            highWaterStore: _MemHwm()),
        machineId: () async => 'M',
        mac: () async => 'AA',
      );

  Future<void> reg(String uuid, String? kind, {DateTime? createdAt}) =>
      PackResultsDb.registerPack(
          packUuid: uuid,
          schoolCode: '999',
          expiresAt: expires,
          kind: kind,
          createdAt: createdAt);

  Future<void> add(String uuid, String key) => PackResultsDb.append(
      packUuid: uuid,
      chainKey: Uint8List(32),
      idempotencyKey: key,
      payloadJson: '{"k":"$key"}');

  group('export layout', () {
    test('monitoring and diagnostic packs land in separate folders', () async {
      await reg(monUuid, 'monitoring', createdAt: created);
      await reg(diagUuid, 'diagnostic', createdAt: created);
      await add(monUuid, 'a');
      await add(diagUuid, 'a');
      final mon = (await exporter().exportPack(monUuid, tmp, schoolCode: '999'))
          .file;
      final diag =
          (await exporter().exportPack(diagUuid, tmp, schoolCode: '999')).file;
      expect(mon.path,
          p.join(tmp.path, '999-maktab_monitoring_${_ymd(created)}',
              '${_ymd(created)}_aaaaaaaa.alochires'));
      expect(diag.path,
          p.join(tmp.path, '999-maktab_diagnostika_${_ymd(created)}',
              '${_ymd(created)}_bbbbbbbb.alochires'));
      expect(mon.existsSync() && diag.existsSync(), isTrue);
    });

    test('two rounds of the same school keep separate dated files', () async {
      const round2 = 'cccccccc-3333-4333-8333-000000000003';
      await reg(monUuid, 'monitoring', createdAt: created);
      await reg(round2, 'monitoring',
          createdAt: created.add(const Duration(days: 21)));
      await add(monUuid, 'a');
      await add(round2, 'a');
      final a = (await exporter().exportPack(monUuid, tmp)).file;
      final b = (await exporter().exportPack(round2, tmp)).file;
      // Different created_at day = different folder, same parent.
      expect(p.dirname(a.path), isNot(p.dirname(b.path)));
      expect(p.dirname(p.dirname(a.path)), p.dirname(p.dirname(b.path)));
      expect(p.basename(a.path), isNot(p.basename(b.path)));
    });

    test('same school/kind/day: second pack gets -2, each pack is stable',
        () async {
      const other = 'cccccccc-3333-4333-8333-000000000003';
      await reg(monUuid, 'monitoring', createdAt: created);
      await reg(other, 'monitoring', createdAt: created);
      await add(monUuid, 'a');
      await add(other, 'a');
      final a1 = (await exporter().exportPack(monUuid, tmp)).file;
      final b1 = (await exporter().exportPack(other, tmp)).file;
      final a2 = (await exporter().exportPack(monUuid, tmp)).file;
      final base = '999-maktab_monitoring_${_ymd(created)}';
      expect(p.basename(p.dirname(a1.path)), base);
      expect(p.basename(p.dirname(b1.path)), '$base-2');
      expect(p.dirname(a2.path), p.dirname(a1.path));
      // latest.alochires lands in the same per-pack folder.
      final dir = await packExportDir(tmp, other);
      expect(p.basename(dir.path), '$base-2');
    });

    test('old layouts are left alone', () async {
      final old1 = File(p.join(tmp.path, '999', 'monitoring', 'x.alochires'))
        ..createSync(recursive: true);
      final old2 = File(p.join(tmp.path, '999_abc', 'latest.alochires'))
        ..createSync(recursive: true);
      await reg(monUuid, 'monitoring', createdAt: created);
      await add(monUuid, 'a');
      await exporter().exportPack(monUuid, tmp);
      expect(old1.existsSync() && old2.existsSync(), isTrue);
    });

    test('school folder name is a safe slug', () {
      expect(schoolFolderName('88'), '88-maktab');
      expect(schoolFolderName(''), 'maktab');
      expect(schoolFolderName(' Ixtisos  maktab/1 '), 'Ixtisos-maktab1');
      expect(schoolFolderName('Мактаб №5'), 'Мактаб-5');
      expect(schoolFolderName('..'), 'maktab');
    });

    test('a taken name gets -2, -3 and is never overwritten', () async {
      await reg(monUuid, 'monitoring', createdAt: created);
      await add(monUuid, 'a');
      final first = (await exporter().exportPack(monUuid, tmp)).file;
      first.writeAsStringSync('keep');
      final second = (await exporter().exportPack(monUuid, tmp)).file;
      final third = (await exporter().exportPack(monUuid, tmp)).file;
      expect(first.readAsStringSync(), 'keep');
      expect(p.basename(second.path), '${_ymd(created)}_aaaaaaaa-2.alochires');
      expect(p.basename(third.path), '${_ymd(created)}_aaaaaaaa-3.alochires');
    });

    test('unknown kind (old stored pack): unknown folder, export-day date',
        () async {
      await reg(monUuid, null); // registered before kind/created_at existed
      await add(monUuid, 'a');
      final f = (await exporter().exportPack(monUuid, tmp)).file;
      expect(f.path,
          p.join(tmp.path, '999-maktab_unknown_${_ymd(exportAt)}',
              '${_ymd(exportAt)}_aaaaaaaa.alochires'));
    });

    test('pack never registered: unknown school and kind', () async {
      await add(monUuid, 'a');
      final f = (await exporter().exportPack(monUuid, tmp)).file;
      expect(p.basename(p.dirname(f.path)),
          startsWith('maktab_unknown_${_ymd(exportAt)}'));
    });

    test('packKindOf: single-kind packs only', () {
      Map<String, dynamic> t(String type) => {'type': type};
      expect(OfflinePackSession.packKindOf([t('test'), t('test')]),
          'monitoring');
      expect(OfflinePackSession.packKindOf([t('diagnostic')]), 'diagnostic');
      expect(OfflinePackSession.packKindOf([t('test'), t('diagnostic')]), isNull);
      expect(OfflinePackSession.packKindOf(const []), isNull);
    });
  });

  group('archive', () {
    test('refused while rows are unexported, allowed after export', () async {
      await reg(monUuid, 'monitoring', createdAt: created);
      await add(monUuid, 'a');
      expect(await PackResultsDb.archivePack(monUuid), isFalse);
      expect(await PackResultsDb.summaries(), hasLength(1));

      await exporter().exportPack(monUuid, tmp);
      expect(await PackResultsDb.archivePack(monUuid), isTrue);
      expect(await PackResultsDb.summaries(), isEmpty);
      final all = await PackResultsDb.summaries(includeArchived: true);
      expect(all.single.archived, isTrue);
      expect(all.single.kind, 'monitoring');
      // Rows are kept.
      expect(await PackResultsDb.rowsForPack(monUuid), hasLength(1));
    });

    test('re-opening a pack keeps the archive flag and the kind', () async {
      await reg(monUuid, 'monitoring', createdAt: created);
      await add(monUuid, 'a');
      await exporter().exportPack(monUuid, tmp);
      await PackResultsDb.archivePack(monUuid);
      await reg(monUuid, 'monitoring', createdAt: created); // open again
      expect(await PackResultsDb.summaries(), isEmpty);
      expect((await PackResultsDb.metaOf(monUuid))!.kind, 'monitoring');
    });

    test('a new result makes an archived pack visible again', () async {
      await reg(monUuid, 'monitoring', createdAt: created);
      await add(monUuid, 'a');
      await exporter().exportPack(monUuid, tmp);
      await PackResultsDb.archivePack(monUuid);
      await add(monUuid, 'b');
      final s = (await PackResultsDb.summaries()).single;
      expect(s.unexported, 1);
      expect(s.archived, isFalse);
    });

    test('expired and fully exported packs are hidden automatically',
        () async {
      await PackResultsDb.registerPack(
          packUuid: monUuid, schoolCode: '999', expiresAt: expires);
      await add(monUuid, 'a');
      final afterExpiry = expires.millisecondsSinceEpoch + 1000;
      // Not exported: stays visible even when expired.
      expect(await PackResultsDb.summaries(nowMs: afterExpiry), hasLength(1));
      await exporter().exportPack(monUuid, tmp);
      expect(await PackResultsDb.summaries(nowMs: afterExpiry), isEmpty);
      // Not expired yet: visible.
      expect(
          await PackResultsDb.summaries(
              nowMs: expires.millisecondsSinceEpoch - 1000),
          hasLength(1));
    });

    test('archived pack still purges like before', () async {
      await reg(monUuid, 'monitoring', createdAt: created);
      await add(monUuid, 'a');
      await exporter().exportPack(monUuid, tmp);
      await PackResultsDb.archivePack(monUuid);
      final later = expires.add(const Duration(days: 400));
      expect(
          await PackResultsDb.purgeExpired(nowMs: later.millisecondsSinceEpoch),
          1);
      expect(await PackResultsDb.rowsForPack(monUuid), isEmpty);
    });
  });
}
