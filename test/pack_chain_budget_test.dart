// The teacher's own pack enforces the same chain budget the LAN hub does
// (HubLimits.maxPackEntries / maxPackPlainBytes): the server rejects a whole
// file above it, so a result that would cross it is refused with kPackFull
// and nothing is appended.
import 'dart:io';

import 'package:alochi_monitoring/core/api/api_client.dart';
import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/local_server/hub_guard.dart';
import 'package:alochi_monitoring/core/offline/export_format.dart';
import 'package:alochi_monitoring/core/offline/offline_errors.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/security/incident_log.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers/lan_test_pack.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  late Directory tmp;
  late OfflinePackSession session;

  setUp(() async {
    tmp = Directory.systemTemp.createTempSync('pack_budget_');
    await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
    session = await OfflinePackSession.open(lanTestPack(), tmp);
    IncidentLog.instance.drain();
  });

  tearDown(() async {
    IncidentLog.instance.drain();
    OfflinePackSession.close();
    await OfflineQueue.resetForTest();
    tmp.deleteSync(recursive: true);
  });

  Future<int> rows() async =>
      (await PackResultsDb.rowsForPack(lanPackUuid)).length;

  Matcher packFull() => isA<ApiException>()
      .having((e) => e.code, 'code', kPackFull)
      .having((e) => e.statusCode, 'status', 507);

  test('below both limits the result is stored and counted', () async {
    session.chainUsage = ChainUsage(1000, HubLimits.maxPackEntries - 1, {});
    await session.recordResult(lanResultPayload(), token: 'ok1');
    expect(await rows(), 1);
    expect(session.chainUsage!.count, HubLimits.maxPackEntries);
  });

  test('entry limit reached -> kPackFull, nothing appended', () async {
    session.chainUsage = ChainUsage(1000, HubLimits.maxPackEntries, {});
    await expectLater(
        session.recordResult(lanResultPayload(), token: 'full1'),
        throwsA(packFull()));
    expect(await rows(), 0);
    expect(session.chainUsage!.count, HubLimits.maxPackEntries);
  });

  test('byte budget would be crossed -> kPackFull, incidents kept', () async {
    session.chainUsage = ChainUsage(HubLimits.maxPackPlainBytes - 10, 5, {});
    IncidentLog.instance.add('focus_lost');
    await expectLater(
        session.recordResult(lanResultPayload(), token: 'full2'),
        throwsA(packFull()));
    expect(await rows(), 0);
    expect(IncidentLog.instance.snapshot, hasLength(1));
  });

  test('a replay of an already stored result is still acknowledged',
      () async {
    await session.recordResult(lanResultPayload(), token: 'dup');
    session.chainUsage = ChainUsage(HubLimits.maxPackPlainBytes, 99999, {});
    final again = await session.recordResult(lanResultPayload(), token: 'dup');
    expect(again.idempotencyKey, 'dup');
    expect(await rows(), 1);
  });

  test('unknown usage is measured from the chain, then enforced', () async {
    session.chainUsage = null;
    await session.recordResult(lanResultPayload(), token: 'm1');
    expect(session.chainUsage, isNotNull);
    expect(session.chainUsage!.count, 1);
  });

  test('kPackFull has a localized message in uz and ru', () async {
    const e = ApiException(507, 'pack full', code: kPackFull);
    for (final lc in const ['uz', 'ru']) {
      final l10n = await AppLocalizations.delegate.load(Locale(lc));
      expect(localizeOfflineError(l10n, e), l10n.usbErrPackFull);
      expect(l10n.usbErrPackFull, isNotEmpty);
    }
  });
}
