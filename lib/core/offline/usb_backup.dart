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

/// In-memory outcome of the last auto-save per pack (UI only; resets on restart).
class AutoSaveEntry {
  final DateTime? lastOkAt;
  final int lastResultCount;

  /// Set by a failed run, cleared by the next successful one.
  final DateTime? lastErrorAt;
  const AutoSaveEntry(this.lastOkAt, this.lastResultCount, this.lastErrorAt);
  bool get failed => lastErrorAt != null;
}

class AutoSaveStatus {
  AutoSaveStatus._();
  static final ValueNotifier<Map<String, AutoSaveEntry>> all = ValueNotifier(
    const {},
  );

  static void ok(String packUuid, int count) => all.value = {
        ...all.value,
        packUuid: AutoSaveEntry(DateTime.now(), count, null),
      };

  static void fail(String packUuid) {
    final prev = all.value[packUuid];
    all.value = {
      ...all.value,
      packUuid: AutoSaveEntry(
        prev?.lastOkAt,
        prev?.lastResultCount ?? 0,
        DateTime.now(),
      ),
    };
  }
}

final _autoSaveRuns = <String, Future<void>>{};
final _autoSaveDirty = <String>{};

/// Fire-and-forget: refreshes `<Downloads>/alochi-offline/<maktab>_<tur>_<date>/latest.alochires`.
/// Never throws and never blocks the caller; failures log the exception type only.
/// Triggers are coalesced per pack: one run in flight plus one dirty flag, so a
/// burst of N results costs at most 2 builds. The returned future (completes
/// once the pack is clean) is for tests; callers ignore it.
Future<void> autoSaveLatest(
  String packUuid,
  String schoolCode, {
  ResultsExporter? exporter,
  Future<Directory> Function()? baseDir,
}) {
  _autoSaveDirty.add(packUuid);
  return _autoSaveRuns[packUuid] ??= () async {
    while (_autoSaveDirty.remove(packUuid)) {
      try {
        final base = await (baseDir ?? defaultExportDir)();
        final dir = await packExportDir(base, packUuid, schoolCode: schoolCode);
        final out = await (exporter ?? ResultsExporter()).writeLatest(
          packUuid,
          dir,
        );
        AutoSaveStatus.ok(packUuid, out.count);
      } catch (e) {
        AutoSaveStatus.fail(packUuid);
        debugPrint('autoSaveLatest failed: ${e.runtimeType}');
      }
    }
    // Same sync turn as the loop check above: no trigger can slip in between.
    _autoSaveRuns.remove(packUuid);
  }();
}

typedef DriveLister = Future<List<String>> Function();

/// Mounted volumes under [root] (`/Volumes` on macOS), minus hidden entries
/// and the boot volume (a symlink resolving to `/`). Sorted by path.
@visibleForTesting
List<String> listMacVolumes([String root = '/Volumes']) {
  final dir = Directory(root);
  if (!dir.existsSync()) return const [];
  final out = <String>[];
  for (final e in dir.listSync(followLinks: false)) {
    if (p.basename(e.path).startsWith('.')) continue;
    try {
      if (!FileSystemEntity.isDirectorySync(e.path)) continue;
      if (e.resolveSymbolicLinksSync() == '/') continue;
    } on FileSystemException {
      continue; // unreadable/dangling entry: not a usable stick
    }
    out.add(e.path);
  }
  return out..sort();
}

/// Removable drive roots such as `E:\` (Windows) or `/Volumes/FLASH` (macOS).
/// Empty elsewhere.
Future<List<String>> listRemovableDrives() async {
  if (Platform.isMacOS) return listMacVolumes();
  if (!Platform.isWindows) return const [];
  final mask = GetLogicalDrives();
  final roots = <String>[
    for (var i = 2; i < 26; i++) // A:/B: are floppy letters
      if (mask & (1 << i) != 0) '${String.fromCharCode(65 + i)}:\\',
  ];
  return selectFlashDrives(
    roots,
    driveType: (r) => _withPtr(r, GetDriveType),
    hasMedia: (r) => _withPtr(r, (ptr) => _hasMedia(ptr)),
    isUsbBus: _isUsbBus,
    systemDrive: Platform.environment['SystemDrive'] ?? 'C:',
  );
}

/// Filter for [listRemovableDrives] (pure, so it is unit-testable off Windows).
/// DRIVE_REMOVABLE with media is always accepted. Many USB sticks/SSDs report
/// DRIVE_FIXED, so those count too when [isUsbBus] says USB, never the system
/// drive, and only with media. A throwing probe skips that drive.
@visibleForTesting
List<String> selectFlashDrives(
  List<String> roots, {
  required int Function(String root) driveType,
  required bool Function(String root) hasMedia,
  required bool Function(String root) isUsbBus,
  required String systemDrive,
}) {
  final sys = systemDrive.substring(0, 1).toUpperCase();
  final out = <String>[];
  for (final root in roots) {
    try {
      final type = driveType(root);
      final ok = type == DRIVE_REMOVABLE ||
          (type == DRIVE_FIXED &&
              root.substring(0, 1).toUpperCase() != sys &&
              isUsbBus(root));
      if (ok && hasMedia(root)) out.add(root);
    } catch (e) {
      debugPrint('drive probe failed: ${e.runtimeType}');
    }
  }
  return out;
}

T _withPtr<T>(String s, T Function(Pointer<Utf16>) f) {
  final ptr = s.toNativeUtf16();
  try {
    return f(ptr);
  } finally {
    calloc.free(ptr);
  }
}

const _busTypeUsb = 7; // STORAGE_BUS_TYPE.BusTypeUsb

/// IOCTL_STORAGE_QUERY_PROPERTY(StorageDeviceProperty) on `\\.\X:`; reads
/// STORAGE_DEVICE_DESCRIPTOR.BusType. Access 0 = query only (no admin needed).
/// Any failure returns false (drive skipped).
bool _isUsbBus(String root) {
  final h = _withPtr(
    '\\\\.\\${root.substring(0, 2)}',
    (path) => CreateFile(path, 0, FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
        OPEN_EXISTING, 0, 0),
  );
  if (h == INVALID_HANDLE_VALUE) return false;
  final query = calloc<Uint8>(12); // PropertyId=0, QueryType=0, 1 spare byte
  final out = calloc<Uint32>(256); // 1024 bytes
  final got = calloc<Uint32>();
  try {
    final ok = DeviceIoControl(
        h, IOCTL_STORAGE_QUERY_PROPERTY, query, 12, out, 1024, got, nullptr);
    if (ok == 0 || got.value < 32) return false;
    return out[7] == _busTypeUsb; // byte offset 28 (little-endian host)
  } finally {
    CloseHandle(h);
    calloc.free(query);
    calloc.free(out);
    calloc.free(got);
  }
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

/// `<folder>/<file>` (new `<maktab>_<tur>_<date>/<file>`, old `<school>/<kind>/<file>`) for an export made under `.../alochi-offline/`, so
/// the flash drive mirrors the Downloads layout; just the file name otherwise.
String _relUnderExportRoot(File src) {
  final parts = p.split(src.path);
  final i = parts.lastIndexOf('alochi-offline');
  return (i < 0 || i >= parts.length - 1)
      ? p.basename(src.path)
      : p.joinAll(parts.sublist(i + 1));
}

/// Copies [src] into `<drive>alochi-offline/` (temp name, then rename) and
/// verifies length + sha256 of the copy. Returns the destination file.
Future<File> copyToFlash(
  File src,
  String drive, {
  Future<void> Function(File src, File dst)? copier,
}) async {
  final dir = Directory(p.join(drive, 'alochi-offline'));
  await dir.create(recursive: true);
  final dest = File(p.join(dir.path, _relUnderExportRoot(src)));
  await dest.parent.create(recursive: true);
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
