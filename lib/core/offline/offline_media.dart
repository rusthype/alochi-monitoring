// lib/core/offline/offline_media.dart
//
// Maps a pack image reference (`media/<sha256>.<ext>`, see offline_pack.py) to
// the extracted file under `offline_store/media/`. Returns null for anything
// that is not a pack reference, so every existing image path (http(s) URLs,
// bundled assets) behaves exactly as before.
import 'dart:io';

import 'package:path/path.dart' as p;

class OfflineMedia {
  OfflineMedia._();

  /// `<appSupport>/offline_store/media` while a pack is open, else null.
  static Directory? root;

  static final RegExp _ref =
      RegExp(r'^media/([0-9a-f]{64}\.(jpg|jpeg|png|gif|webp))$');

  static File? fileFor(String? ref) {
    final dir = root;
    if (dir == null || ref == null) return null;
    final m = _ref.firstMatch(ref.trim());
    if (m == null) return null;
    return File(p.join(dir.path, m.group(1)!));
  }
}
