// Saved-result rows in the offline dialog: "<Kind> · <School>" title and a
// "date · last result HH:mm · pack <short id>" line (no more identical rows).
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/features/offline/offline_control_center_dialog.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

final Uint8List _key = Uint8List.fromList(List.generate(32, (i) => i + 1));
const _diagPayload = '{"answers":[{"q":"q1","a":"x"}]}';
const _pathProvider = MethodChannel('plugins.flutter.io/path_provider');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('rows show kind+school, date line with short id, null-kind fallback',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = Directory.systemTemp.createTempSync('pack_row_');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    // QueueCrypto's fallback key file lives under path_provider.
    messenger.setMockMethodCallHandler(_pathProvider, (call) async => tmp.path);
    addTearDown(() async {
      messenger.setMockMethodCallHandler(_pathProvider, null);
      await tester.runAsync(() async {
        await OfflineQueue.resetForTest();
        tmp.deleteSync(recursive: true);
      });
    });
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final created = DateTime.utc(2026, 11, 8, 9, 0);
    final lastMs = DateTime.utc(2026, 11, 8, 15, 58).millisecondsSinceEpoch;

    await tester.runAsync(() async {
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      Future<void> pack(String uuid, String school, String? kind,
          DateTime? createdAt, String payload) async {
        await PackResultsDb.registerPack(
            packUuid: uuid,
            schoolCode: school,
            expiresAt: DateTime.utc(2099),
            kind: kind,
            createdAt: createdAt);
        await PackResultsDb.append(
            packUuid: uuid,
            chainKey: _key,
            idempotencyKey: 'k',
            payloadJson: payload,
            nowMs: lastMs);
      }

      // known kind + manifest date
      await pack(
          '4ce722d9-0000-0000-0000-000000000001', '39', 'monitoring', created, '{}');
      // legacy pack: kind inferred from the stored diagnostic payload
      await pack('aaaaaaaa-0000-0000-0000-000000000002', '40', null, null,
          _diagPayload);
      // legacy pack, nothing recognisable: no guess, school only
      await pack('bbbbbbbb-0000-0000-0000-000000000003', '41', null, null, '{}');
    });

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
          body: SingleChildScrollView(child: OfflineControlCenterDialog())),
    ));
    // Real IO completes outside the fake-async zone: alternate waits and pumps.
    for (var i = 0; i < 100; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    String hm(int ms) => DateFormat('HH:mm')
        .format(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal());
    String dmy(DateTime d) => DateFormat('dd.MM.yyyy').format(d.toLocal());
    final lastDay = DateTime.fromMillisecondsSinceEpoch(lastMs, isUtc: true);

    expect(find.text('Мониторинг · Школа 39'), findsOneWidget);
    expect(
        find.text('${dmy(created)} · последний результат ${hm(lastMs)} '
            '· пакет 4ce722d9'),
        findsOneWidget);

    // inferred from the payload; date falls back to the last result's day
    expect(find.text('Диагностика · Школа 40'), findsOneWidget);
    expect(
        find.text('${dmy(lastDay)} · последний результат ${hm(lastMs)} '
            '· пакет aaaaaaaa'),
        findsOneWidget);

    // unknown kind: just the school, never a wrong guess
    expect(find.text(l10n.usbSchoolLabel('41')), findsOneWidget);
    expect(find.textContaining('· Школа 41'), findsNothing);
  });
}
