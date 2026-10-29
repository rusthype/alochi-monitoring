// Regression: picking a pack in the Offline mode dialog must reach the PIN
// prompt. The pack inspection runs in Isolate.run from inside a State method;
// the closure must not drag the State (or anything unsendable) along.
// ignore_for_file: prefer_const_constructors
import 'dart:io';

import 'package:alochi_monitoring/core/db/offline_queue.dart';
import 'package:alochi_monitoring/core/offline/lan_client_session.dart';
import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/core/offline/offline_session.dart';
import 'package:alochi_monitoring/core/offline/pack_loader.dart';
import 'package:alochi_monitoring/core/security/monitored_clock.dart';
import 'package:alochi_monitoring/features/offline/offline_control_center_dialog.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _dir = 'test/fixtures/offline';

class _CancelPicker extends FilePicker with MockPlatformInterfaceMixin {
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      null;
}

class _FakePicker extends FilePicker with MockPlatformInterfaceMixin {
  _FakePicker(this.path);
  final String path;
  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult(
          [PlatformFile(name: 'golden.alochipack', size: 0, path: path)]);
}

/// Pack expiry now reads the persisted high-water mark (F24). Widget tests
/// have no flutter_secure_storage plugin: its failing channel call only
/// completes on fake-zone timers, which would hold back the isolate start.
class _MemHwm implements HighWaterStore {
  @override
  Future<DateTime?> read() async => null;
  @override
  Future<void> write(DateTime utc) async {}
}

void main() {
  late OfflineKeys saved;
  late MonitoredClock savedClock;
  setUp(() {
    savedClock = MonitoredClock.instance;
    MonitoredClock.instance = MonitoredClock(highWaterStore: _MemHwm());
    saved = OfflineKeys.current;
    OfflineKeys.current = OfflineKeys(
      signingPem: File('$_dir/test_signing_public.pem').readAsStringSync(),
      resultsPem: File('$_dir/test_results_public.pem').readAsStringSync(),
    );
  });
  tearDown(() {
    OfflineKeys.current = saved;
    MonitoredClock.instance = savedClock;
  });

  testWidgets('golden pack picked in the dialog reaches the PIN prompt',
      (tester) async {
    FilePicker.platform = _FakePicker('$_dir/golden.alochipack');
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: OfflineControlCenterDialog()),
    ));
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;

    await tester.tap(find.text(l10n.usbLoadPack));
    // Real isolate + real file IO: let the event loop run for real.
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(seconds: 3)));
    await tester.pump();

    expect(find.text(l10n.usbErrRead), findsNothing);
    expect(find.text(l10n.usbPinTitle), findsOneWidget);
  });

  testWidgets('cancelling the file dialog keeps the already open pack',
      (tester) async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    final tmp = Directory.systemTemp.createTempSync('dlg_cancel_');
    addTearDown(() async {
      exitOfflineMode();
      await OfflineQueue.resetForTest();
      tmp.deleteSync(recursive: true);
    });
    await tester.runAsync(() async {
      await OfflineQueue.openAtPath(p.join(tmp.path, 'q.db'));
      final media = Directory(p.join(tmp.path, 'media'))..createSync();
      final pack = await PackLoader(keys: OfflineKeys.current).open(
          File('$_dir/golden.alochipack').readAsBytesSync(), '12345678',
          mediaDir: media);
      await OfflinePackSession.open(pack, media);
    });
    final opened = OfflinePackSession.current;
    expect(opened, isNotNull);

    FilePicker.platform = _CancelPicker();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: OfflineControlCenterDialog()),
    ));
    await tester.pump();
    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    expect(find.text(l10n.usbNoPackOpen), findsNothing);

    await tester.tap(find.text(l10n.usbLoadPack));
    await tester.pump();
    await tester.pump();

    expect(identical(OfflinePackSession.current, opened), isTrue);
    expect(find.text(l10n.usbNoPackOpen), findsNothing);
    expect(find.text(l10n.usbStartTests), findsOneWidget);
  });
}
