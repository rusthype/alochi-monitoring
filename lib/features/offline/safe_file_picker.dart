import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// file_picker 8.x on Windows calls COMDLG32 / IFileOpenDialog through FFI
/// with no owner window by default (and pickFiles from a short-lived worker
/// isolate). A second dialog opened while one is up, or an exception from the
/// native call, has crashed the app with 0xc0000005 in COMDLG32.dll. Funnel
/// every pick through one guarded call: owner window locked, one dialog at a
/// time, failures become "cancelled" instead of killing the process.
bool _pickerOpen = false;

Future<String?> pickPackFile({required String title}) async {
  if (_pickerOpen) return null;
  _pickerOpen = true;
  try {
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: title,
      type: FileType.custom,
      allowedExtensions: const ['alochipack'],
      lockParentWindow: true,
    );
    final files = picked?.files;
    return (files == null || files.isEmpty) ? null : files.first.path;
  } catch (e) {
    debugPrint('pickPackFile failed: ${e.runtimeType}');
    return null;
  } finally {
    _pickerOpen = false;
  }
}

/// Export target without any folder dialog: `<Downloads>/alochi-offline`.
Future<Directory> defaultExportDir() async {
  final base =
      await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
  return Directory(p.join(base.path, 'alochi-offline')).create(recursive: true);
}
