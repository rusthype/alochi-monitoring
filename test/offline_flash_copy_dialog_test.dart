// The dialog's "copy to flash drive" flow, driven through the injectable
// listDrives with temp dirs standing in for drives.
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/db/pack_results_db.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/theme/app_colors.dart';
import 'package:alochi_monitoring/features/offline/export_done_notice.dart';
import 'package:alochi_monitoring/core/offline/usb_backup.dart'
    show AutoSaveStatus, DriveLister;
import 'package:alochi_monitoring/features/offline/offline_control_center_dialog.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Every directory is [path]. The MethodChannel mock alone is not enough:
/// on Windows `getDownloadsDirectory` throws UnsupportedError in the channel
/// implementation (the real plugin is a separate Dart package there), which
/// made the product code's catch-all report "flash copy failed".
class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.path);
  final String path;
  @override
  Future<String?> getDownloadsPath() async => path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
}

const _fixtures = 'test/fixtures/offline';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OfflineKeys saved;
  late Directory tmp;
  late PathProviderPlatform savedPaths;

  setUp(() {
    saved = OfflineKeys.current;
    OfflineKeys.current = OfflineKeys(
      signingPem: File('$_fixtures/test_signing_public.pem').readAsStringSync(),
      resultsPem: File('$_fixtures/test_results_public.pem').readAsStringSync(),
    );
    tmp = Directory.systemTemp.createTempSync('flash_dlg_');
    savedPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });
  tearDown(() {
    OfflineKeys.current = saved;
    PathProviderPlatform.instance = savedPaths;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
  });

  // Real IO completes outside the fake-async zone: alternate real waits and pumps.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)));
      await tester.pump();
    }
  }

  Future<void> pump(WidgetTester tester, DriveLister drives,
      {List<String> packs = const ['pk-one-uuid'], bool register = false}) async {
    tester.view.physicalSize = const Size(1000, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (call) async => tmp.path);
    addTearDown(() async {
      await tester.runAsync(() async {
        await OfflineQueue.resetForTest();
        tmp.deleteSync(recursive: true);
      });
    });
    await tester.runAsync(() async {
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      for (final uuid in packs) {
        if (register) {
          await PackResultsDb.registerPack(
              packUuid: uuid,
              schoolCode: '9',
              expiresAt: DateTime.now().add(const Duration(days: 30)),
              kind: 'monitoring');
        }
        await PackResultsDb.append(
            packUuid: uuid,
            chainKey: Uint8List(32),
            idempotencyKey: 'k',
            payloadJson: '{"x":1}',
            incidents: const [],
            clockFlags: const []);
      }
    });
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: OfflineControlCenterDialog(listDrives: drives)),
    ));
    await settle(tester); // summaries load
  }

  AppLocalizations l10nOf(WidgetTester t) =>
      AppLocalizations.of(t.element(find.byType(Scaffold)))!;

  Future<void> tapFlash(WidgetTester tester) async {
    await tester.tap(find.text(l10nOf(tester).usbFlashButton));
    await settle(tester);
  }

  Directory drive(String n) => Directory(p.join(tmp.path, n))..createSync();

  // Exports now live in <root>/<school>/<kind>/: list files recursively.
  List<File> filesUnder(Directory d) =>
      d.listSync(recursive: true).whereType<File>().toList();

  testWidgets('auto-save line: nothing unknown, warning on fail, ok after',
      (tester) async {
    AutoSaveStatus.all.value = const {};
    addTearDown(() => AutoSaveStatus.all.value = const {});
    await pump(tester, () async => const []);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.autoSaveFailed), findsNothing); // no entry = unknown

    AutoSaveStatus.fail('pk-one-uuid');
    await tester.pump();
    expect(find.text(l10n.autoSaveFailed), findsOneWidget);

    AutoSaveStatus.ok('pk-one-uuid', 1);
    await tester.pump();
    expect(find.text(l10n.autoSaveFailed), findsNothing);
    expect(find.textContaining('1'), findsWidgets);
    expect(find.textContaining(l10n.autoSaveOk('', 1).split(':').first),
        findsOneWidget);

    AutoSaveStatus.fail('pk-one-uuid');
    await tester.pump();
    expect(find.text(l10n.autoSaveFailed), findsOneWidget);
  });

  testWidgets('no drive: shows the no-flash message', (tester) async {
    await pump(tester, () async => const []);
    await tapFlash(tester);
    expect(find.text(l10nOf(tester).usbFlashNone), findsOneWidget);
  });

  testWidgets('single drive: copies and reports the path', (tester) async {
    final e = drive('E');
    await pump(tester, () async => [e.path]);
    await tapFlash(tester);
    final copied = filesUnder(Directory(p.join(e.path, 'alochi-offline')));
    expect(copied, hasLength(1));
    // Mirrors the Downloads layout: <school>/<kind>/<file> (no pack_meta here).
    expect(p.relative(copied.single.path, from: p.join(e.path, 'alochi-offline')),
        startsWith(p.join('unknown', 'unknown')));
    // Success notice: green widget, headline, file name on its own line.
    expect(find.text(l10nOf(tester).usbFlashReady), findsOneWidget);
    expect(find.text(p.basename(copied.single.path)), findsOneWidget);
    expect(find.byType(ExportDoneNotice), findsOneWidget);
    expect(find.text(l10nOf(tester).usbCopyPath), findsOneWidget);
    expect(find.text(l10nOf(tester).usbRevealInFolder), findsOneWidget);
  });

  testWidgets('per-pack export: green notice with count and file name',
      (tester) async {
    await pump(tester, () async => const []);
    await tester.ensureVisible(find.text(l10nOf(tester).usbExportOne));
    await tester.tap(find.text(l10nOf(tester).usbExportOne));
    await settle(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.usbExportedHeadline(1)), findsOneWidget);
    final box = tester.widget<Container>(find
        .descendant(
            of: find.byType(ExportDoneNotice), matching: find.byType(Container))
        .first);
    expect((box.decoration! as BoxDecoration).color, AppColors.successMuted);
    final files = filesUnder(Directory(p.join(tmp.path, 'alochi-offline')));
    expect(files, hasLength(1));
    expect(find.text(p.basename(files.single.path)), findsOneWidget);
    expect(find.text(l10n.usbCopyPath), findsOneWidget);
  });

  testWidgets('several drives + several packs: one pick, all packs copied',
      (tester) async {
    final e = drive('E'), f = drive('F');
    var lists = 0;
    await pump(tester, () async {
      lists++;
      return [e.path, f.path];
    }, packs: ['pk-one-uuid', 'pack-two-uuid']);
    await tapFlash(tester);
    expect(find.text(l10nOf(tester).usbFlashPick), findsOneWidget);
    await tester.tap(find.text(f.path));
    await settle(tester);
    expect(lists, 1);
    expect(find.text(l10nOf(tester).usbFlashPick), findsNothing);
    expect(filesUnder(Directory(p.join(f.path, 'alochi-offline'))), hasLength(2));
    expect(Directory(p.join(e.path, 'alochi-offline')).existsSync(), isFalse);
  });

  testWidgets('copy failure: shows the failed message', (tester) async {
    // A file where the drive root should be: creating alochi-offline fails.
    final bad = File(p.join(tmp.path, 'notadrive'))..writeAsStringSync('x');
    await pump(tester, () async => [bad.path]);
    await tapFlash(tester);
    expect(find.text(l10nOf(tester).usbFlashFailed), findsOneWidget);
  });

  testWidgets(
      'archive: disabled with unexported rows; archived pack is hidden and '
      'skipped by export-all', (tester) async {
    await pump(tester, () async => const [],
        packs: ['pk-one-uuid', 'pack-two-uuid'], register: true);
    final l10n = l10nOf(tester);
    final archive = find.widgetWithText(TextButton, l10n.usbArchiveOne);
    expect(archive, findsNWidgets(2));
    for (final b in tester.widgetList<TextButton>(archive)) {
      expect(b.onPressed, isNull); // nothing exported yet
    }

    // Export the first listed pack only, then archive it.
    final exportOne = find.widgetWithText(TextButton, l10n.usbExportOne).first;
    await tester.ensureVisible(exportOne);
    await tester.tap(exportOne);
    await settle(tester);
    final enabled = tester
        .widgetList<TextButton>(archive)
        .where((b) => b.onPressed != null)
        .length;
    expect(enabled, 1);
    await tester.ensureVisible(archive.first);
    await tester.tap(archive.first);
    await settle(tester);
    // The exported pack was archived (whichever row held it): one row left.
    expect(find.widgetWithText(TextButton, l10n.usbArchiveOne), findsOneWidget);
    expect(find.widgetWithText(TextButton, l10n.usbExportOne), findsOneWidget);
    expect(await tester.runAsync(() => PackResultsDb.summaries()), hasLength(1));

    // Export-all only touches the remaining, non-archived pack.
    final before = filesUnder(Directory(p.join(tmp.path, 'alochi-offline')));
    await tester.ensureVisible(find.text(l10n.usbExportResults));
    await tester.tap(find.text(l10n.usbExportResults));
    await settle(tester);
    final after = filesUnder(Directory(p.join(tmp.path, 'alochi-offline')));
    expect(after.length, before.length + 1);
  });
}
