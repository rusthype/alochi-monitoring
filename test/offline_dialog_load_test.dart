// Regression: picking a pack in the Offline mode dialog must reach the PIN
// prompt. The pack inspection runs in Isolate.run from inside a State method;
// the closure must not drag the State (or anything unsendable) along.
// ignore_for_file: prefer_const_constructors
import 'dart:io';

import 'package:alochi_monitoring/core/offline/offline_keys.dart';
import 'package:alochi_monitoring/features/offline/offline_control_center_dialog.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _dir = 'test/fixtures/offline';

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

void main() {
  late OfflineKeys saved;
  setUp(() {
    saved = OfflineKeys.current;
    OfflineKeys.current = OfflineKeys(
      signingPem: File('$_dir/test_signing_public.pem').readAsStringSync(),
      resultsPem: File('$_dir/test_results_public.pem').readAsStringSync(),
    );
  });
  tearDown(() => OfflineKeys.current = saved);

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
}
