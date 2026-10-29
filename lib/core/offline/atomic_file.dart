// lib/core/offline/atomic_file.dart
//
// Crash- and full-disk-safe file writes for the offline flow: the bytes go to
// `<target>.tmp`, are read back and compared (length + SHA-256) and only then
// renamed onto the final name, so a cut USB stick or a crash can never leave a
// truncated file under the real name.
import 'dart:io';
import 'dart:typed_data';

import 'offline_crypto.dart';

/// Suffix of the in-flight copy.
const String kTmpSuffix = '.tmp';

/// Writes [bytes] to [target] atomically. Throws (and leaves no temp file and
/// no change to [target]) when the write, the read-back check or the rename
/// fails. [write] replaces the temp-file write (tests simulate a short write).
Future<void> writeFileVerified(File target, Uint8List bytes,
    {Future<void> Function(File tmp, Uint8List bytes)? write}) async {
  final tmp = File('${target.path}$kTmpSuffix');
  try {
    await (write ?? (f, b) => f.writeAsBytes(b, flush: true))(tmp, bytes);
    final back = await tmp.readAsBytes();
    if (back.length != bytes.length ||
        OfflineCrypto.sha256Hex(back) != OfflineCrypto.sha256Hex(bytes)) {
      throw FileSystemException(
          'written file differs from its source (${back.length} of '
          '${bytes.length} bytes)',
          tmp.path);
    }
    try {
      await tmp.rename(target.path);
    } catch (_) {
      // The target may be briefly locked (Windows): retry once.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      await tmp.rename(target.path);
    }
  } catch (_) {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
    rethrow;
  }
}

/// Removes `*.tmp` leftovers of an interrupted [writeFileVerified] in [dir].
/// Best effort; never throws.
Future<void> cleanStrayTemps(Directory dir) async {
  try {
    if (!await dir.exists()) return;
    await for (final e in dir.list(followLinks: false)) {
      if (e is File && e.path.endsWith(kTmpSuffix)) {
        try {
          await e.delete();
        } catch (_) {}
      }
    }
  } catch (_) {}
}
