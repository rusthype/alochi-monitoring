// lib/core/offline/usb_backup.dart
//
// Two helpers around the `.alochires` export:
//  * [autoSaveLatest]: silent safety backup after each saved result.
//  * [copyToFlash]/[listRemovableDrives]: "copy to the flash drive" flow.
// Nothing here ever deletes a file.
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:win32/win32.dart';

import '../../features/offline/safe_file_picker.dart' show defaultExportDir;
import 'results_exporter.dart';

final _autoSaveRuns = <String, Future<void>>{};
final _autoSaveDirty = <String>{};

/// Fire-and-forget: refreshes `<Downloads>/alochi-offline/<school>_<uuid8>/latest.alochires`.
/// Never throws and never blocks the caller; failures log the exception type only.
/// Triggers are coalesced per pack: one run in flight plus one dirty flag, so a
/// burst of N results costs at most 2 builds. The returned future (completes
/// once the pack is clean) is for tests; callers ignore it.
Future<void> autoSaveLatest(String packUuid, String schoolCode,
    {ResultsExporter? exporter, Future<Directory> Function()? baseDir}) {
  _autoSaveDirty.add(packUuid);
  return _autoSaveRuns[packUuid] ??= () async {
    while (_autoSaveDirty.remove(packUuid)) {
      try {
        final base = await (baseDir ?? defaultExportDir)();
        final dir =
            Directory(p.join(base.path, packFilePrefix(packUuid, schoolCode)));
        await (exporter ?? ResultsExporter()).writeLatest(packUuid, dir);
      } catch (e) {
        debugPrint('autoSaveLatest failed: ${e.runtimeType}');
      }
    }
    // Same sync turn as the loop check above: no trigger can slip in between.
    _autoSaveRuns.remove(packUuid);
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
      // A:/B: are floppy letters; an empty card reader has no media.
      if (i > 1 && GetDriveType(ptr) == DRIVE_REMOVABLE && _hasMedia(ptr)) {
        out.add(root);
      }
    } finally {
      calloc.free(ptr);
    }
  }
  return out;
}

bool _hasMedia(Pointer<Utf16> root) {
  final total = calloc<Uint64>();
  try {
    return GetDiskFreeSpaceEx(root, nullptr, total, nullptr) != 0;
  } finally {
    calloc.free(total);
  }
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
  // Flush to the device before verifying, so a pulled stick cannot hold a
  // verified-in-cache but half-written file.
  final raf = await tmp.open(mode: FileMode.append);
  try {
    await raf.flush();
  } finally {
    await raf.close();
  }
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

  /// Every file already copied onto the drive (also set on a later failure).
  final List<String> paths;
  const FlashResult(this.status, [this.paths = const []]);
  String? get path => paths.isEmpty ? null : paths.last;
}

/// Drive first (so "no flash drive" does not stamp anything), picked ONCE; then
/// for each of [exports]: export into Downloads as usual, copy + verify onto
/// the drive. A failed copy keeps the Downloads file; packs already copied stay
/// reported in [FlashResult.paths]. An [ExportException] from an export is
/// NOT mapped here (the caller shows the matching message).
Future<FlashResult> exportToFlash({
  required List<Future<File> Function()> exports,
  required DriveLister drives,
  required Future<String?> Function(List<String> drives) pick,
  Future<void> Function(File src, File dst)? copier,
}) async {
  final found = await drives();
  if (found.isEmpty) return const FlashResult(FlashStatus.noDrive);
  final drive = found.length == 1 ? found.first : await pick(found);
  if (drive == null) return const FlashResult(FlashStatus.cancelled);
  final copied = <String>[];
  for (final export in exports) {
    final file = await export();
    try {
      copied.add((await copyToFlash(file, drive, copier: copier)).path);
    } catch (e) {
      debugPrint('exportToFlash failed: ${e.runtimeType}');
      return FlashResult(FlashStatus.failed, copied);
    }
  }
  return FlashResult(FlashStatus.ok, copied);
}
