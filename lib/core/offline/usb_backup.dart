// lib/core/offline/usb_backup.dart
//
// Two helpers around the `.alochires` export:
//  * [autoSaveLatest]: silent safety backup after each saved result.
//  * [copyToFlash]/[listRemovableDrives]: "copy to the flash drive" flow.
// Nothing here ever deletes a file.
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../../features/offline/safe_file_picker.dart' show defaultExportDir;
import 'results_exporter.dart';

/// Fire-and-forget: refreshes `<Downloads>/alochi-offline/<school>_<uuid8>/latest.alochires`.
/// Never throws and never blocks the caller; failures log the exception type only.
void autoSaveLatest(String packUuid, String schoolCode,
    {ResultsExporter? exporter, Future<Directory> Function()? baseDir}) {
  () async {
    try {
      final base = await (baseDir ?? defaultExportDir)();
      final school = schoolCode.isEmpty ? '' : '${schoolCode}_';
      final dir =
          Directory(p.join(base.path, '$school${packUuid.substring(0, 8)}'));
      await (exporter ?? ResultsExporter()).writeLatest(packUuid, dir);
    } catch (e) {
      debugPrint('autoSaveLatest failed: ${e.runtimeType}');
    }
  }();
}

typedef DriveLister = Future<List<String>> Function();

/// Removable drive roots such as `E:\`. Empty off Windows.
Future<List<String>> listRemovableDrives() async {
  if (!Platform.isWindows) return const [];
  final mask = GetLogicalDrives();
  final out = <String>[];
  for (var i = 0; i < 26; i++) {
    if (mask & (1 << i) == 0) continue;
    final root = '${String.fromCharCode(65 + i)}:\\';
    final ptr = root.toNativeUtf16();
    try {
      if (GetDriveType(ptr) == DRIVE_REMOVABLE) out.add(root);
    } finally {
      calloc.free(ptr);
    }
  }
  return out;
}

class FlashCopyException implements Exception {
  final String reason;
  const FlashCopyException(this.reason);
  @override
  String toString() => 'FlashCopyException($reason)';
}

/// Copies [src] into `<drive>alochi-offline/` (temp name, then rename) and
/// verifies length + sha256 of the copy. Returns the destination file.
Future<File> copyToFlash(File src, String drive,
    {Future<void> Function(File src, File dst)? copier}) async {
  final dir = Directory(p.join(drive, 'alochi-offline'));
  await dir.create(recursive: true);
  final dest = File(p.join(dir.path, p.basename(src.path)));
  final tmp = File('${dest.path}.part');
  await (copier ?? (a, b) => a.copy(b.path))(src, tmp);
  if (await tmp.length() != await src.length() ||
      (await sha256.bind(tmp.openRead()).first) !=
          (await sha256.bind(src.openRead()).first)) {
    // The bad .part file is left in place (nothing is ever deleted).
    throw const FlashCopyException('size_mismatch');
  }
  await tmp.rename(dest.path);
  return dest;
}

enum FlashStatus { noDrive, cancelled, ok, failed }

class FlashResult {
  final FlashStatus status;
  final String? path;
  const FlashResult(this.status, [this.path]);
}

/// Drive first (so "no flash drive" does not stamp anything), then [export]
/// into Downloads as usual, then copy + verify onto the drive. A failed copy
/// keeps the Downloads file.
Future<FlashResult> exportToFlash({
  required Future<File> Function() export,
  required DriveLister drives,
  required Future<String?> Function(List<String> drives) pick,
  Future<void> Function(File src, File dst)? copier,
}) async {
  final found = await drives();
  if (found.isEmpty) return const FlashResult(FlashStatus.noDrive);
  final drive = found.length == 1 ? found.first : await pick(found);
  if (drive == null) return const FlashResult(FlashStatus.cancelled);
  try {
    final copy = await copyToFlash(await export(), drive, copier: copier);
    return FlashResult(FlashStatus.ok, copy.path);
  } catch (e) {
    debugPrint('exportToFlash failed: ${e.runtimeType}');
    return const FlashResult(FlashStatus.failed);
  }
}
