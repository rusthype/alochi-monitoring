// Finished screen while a USB pack is open: nothing was sent and nothing is
// scored, so it must say "saved" and must not show the green "synced" badge.
import 'dart:io';
import 'dart:typed_data';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_finished_screen.dart';
import 'package:alochi_monitoring/features/diagnostic/widgets/sync_status_badge.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('pack mode: saved wording, no score, no sync badge',
      (tester) async {
    late Directory tmp;
    await tester.runAsync(() async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      tmp = Directory.systemTemp.createTempSync('offline_diag_fin_');
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      await OfflinePackSession.open(
          LoadedPack(
            manifest: PackManifest(
              formatVersion: 1,
              packUuid: '00000000-0000-4000-8000-0000000000a1',
              schoolId: '00000000-0000-4000-8000-0000000000b2',
              schoolCode: '999',
              createdAt: DateTime.utc(2026, 1, 1),
              expiresAt: DateTime.utc(2099, 1, 1),
              kdfIter: 1,
              kdfSalt: Uint8List(16),
              files: const {},
            ),
            tests: const [],
            groups: const [],
            students: const [],
            chainKey: Uint8List(32),
          ),
          Directory(p.join(tmp.path, 'media')));
    });

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: DiagnosticFinishedScreen(
          studentName: 'Valiyev Ali', subjectsCompleted: ['math', 'english']),
    ));
    // Let the staggered star timers fire (well before the 15s auto-return).
    await tester.pump(const Duration(seconds: 3));
    final l10n =
        AppLocalizations.of(tester.element(find.byType(Scaffold).first))!;
    expect(find.text(l10n.usbSavedTitle), findsOneWidget);
    expect(find.text(l10n.diagnosticFinishedSubmittedPill), findsNothing);
    expect(find.byType(SyncStatusBadge), findsNothing);
    expect(find.textContaining('%'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());

    await tester.runAsync(() async {
      OfflinePackSession.close();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });
  });
}
