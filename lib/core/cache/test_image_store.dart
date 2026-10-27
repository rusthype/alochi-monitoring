// lib/core/cache/test_image_store.dart
//
// Persistent, manifest-less store for the question images of DOWNLOADED
// monitoring tests: <appSupport>/test_images/<sha256(url)>.img. A file's
// existence (size > 0) IS the manifest — no DB, no LRU index to lose on an
// abrupt quit (flutter_cache_manager's JSON index is written lazily and
// drifted from the files on disk). Files are written to a temp name and
// atomically renamed only after a complete, validated download.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Outcome of a successful [TestImageStore.fetch] round-trip.
enum StoreFetch {
  /// Valid file is now on disk.
  stored,

  /// Server answered 404/410: the asset does not exist. Not stored.
  missing,
}

class TestImageStore {
  TestImageStore({
    Directory? root,
    http.Client? client,
    this.timeout = const Duration(seconds: 30),
  })  : _root = root,
        _clientOverride = client;

  /// Process-wide store; [init] is awaited once from main().
  static final TestImageStore instance = TestImageStore();

  Directory? _root;
  final http.Client? _clientOverride;
  http.Client? _lazyClient;
  final Duration timeout;

  http.Client get _client =>
      _clientOverride ?? (_lazyClient ??= http.Client());

  /// Resolves (and creates) the store directory. Safe to call repeatedly.
  Future<void> init() async {
    var root = _root;
    if (root == null) {
      final base = await getApplicationSupportDirectory();
      root = Directory(p.join(base.path, 'test_images'));
      _root = root;
    }
    if (!root.existsSync()) root.createSync(recursive: true);
  }

  /// Where [url]'s image lives (whether or not it exists yet). Null until
  /// [init] has resolved the directory.
  File? _fileFor(String url) {
    final root = _root;
    if (root == null) return null;
    final name = sha256.convert(utf8.encode(url)).toString();
    return File(p.join(root.path, '$name.img'));
  }

  /// The stored image for [url], synchronously, or null. Used by the renderer
  /// so a stored image shows on the very first frame.
  File? cachedFile(String url) {
    try {
      final f = _fileFor(url);
      if (f == null || !f.existsSync() || f.lengthSync() <= 0) return null;
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Downloads [url] into the store. Returns [StoreFetch.missing] for 404/410
  /// and throws on any other failure (network, timeout, bad status, empty or
  /// truncated body) — nothing partial is ever left under the final name.
  Future<StoreFetch> fetch(String url) async {
    final dest = _fileFor(url);
    if (dest == null) throw StateError('TestImageStore not initialised');
    final req = http.Request('GET', Uri.parse(url))
      ..headers['User-Agent'] = 'AlochiMonitoring/1.0';
    final resp = await _client.send(req).timeout(timeout);
    if (resp.statusCode == 404 || resp.statusCode == 410) {
      await resp.stream.drain<void>().timeout(timeout);
      return StoreFetch.missing;
    }
    if (resp.statusCode != 200) {
      await resp.stream.drain<void>().timeout(timeout);
      throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(url));
    }
    final bytes = await resp.stream.toBytes().timeout(timeout);
    final expected = resp.contentLength;
    if (bytes.isEmpty || (expected != null && expected != bytes.length)) {
      throw HttpException('incomplete body (${bytes.length}/$expected)',
          uri: Uri.parse(url));
    }
    final tmp = File('${dest.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(dest.path);
    return StoreFetch.stored;
  }

  /// Best-effort GC: deletes stored images not in [keepUrls] and stale temp
  /// files, but only those untouched for [minAge] (protects images of a
  /// download that is racing the GC and of tests that were never put in
  /// TestCache, e.g. the self-login flow). Never throws.
  Future<void> gc(Set<String> keepUrls,
      {Duration minAge = const Duration(days: 1)}) async {
    try {
      final root = _root;
      if (root == null || !root.existsSync()) return;
      final keep = {
        for (final u in keepUrls) p.basename(_fileFor(u)!.path),
      };
      final cutoff = DateTime.now().subtract(minAge);
      for (final e in root.listSync(followLinks: false)) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        if (keep.contains(name)) continue;
        if (!name.endsWith('.img') && !name.endsWith('.tmp')) continue;
        try {
          if (e.lastModifiedSync().isAfter(cutoff)) continue;
          e.deleteSync();
        } catch (err) {
          debugPrint('TestImageStore.gc: $name: $err');
        }
      }
    } catch (e) {
      debugPrint('TestImageStore.gc failed: $e');
    }
  }
}
