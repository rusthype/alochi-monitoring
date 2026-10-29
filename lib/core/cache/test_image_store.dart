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

  /// Server answered 404/410/403/other permanent 4xx: the asset cannot be
  /// had. Not stored.
  missing,
}

class TestImageStore {
  TestImageStore({
    Directory? root,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxDuration = const Duration(minutes: 3),
  })  : _root = root,
        _clientOverride = client;

  /// Process-wide store; [init] is awaited once from main().
  static TestImageStore _instance = TestImageStore();
  static TestImageStore get instance => _instance;

  @visibleForTesting
  static set instanceForTest(TestImageStore s) => _instance = s;

  Directory? _root;
  final http.Client? _clientOverride;
  http.Client? _lazyClient;

  /// Max silence on the connection: the response headers, and every body
  /// chunk, must arrive within this long. A slow but alive link finishes.
  final Duration timeout;

  /// Hard ceiling for one whole download, however steadily it trickles.
  final Duration maxDuration;

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
    if (!_cleaned) {
      _cleaned = true;
      _cleanLeftovers(root);
    }
  }

  bool _cleaned = false;
  static final RegExp _finished = RegExp(r'^[0-9a-f]{64}\.img$');

  /// Power-cut recovery: anything in the folder that is not a finished
  /// `<sha256>.img` (temp/`.part` files from an interrupted write) and older
  /// than a few minutes is deleted, as is any zero-byte `.img`. Never throws.
  void _cleanLeftovers(Directory root, {Duration minAge = const Duration(minutes: 3)}) {
    try {
      final cutoff = DateTime.now().subtract(minAge);
      for (final e in root.listSync(followLinks: false)) {
        if (e is! File) continue;
        try {
          final name = p.basename(e.path);
          if (_finished.hasMatch(name)) {
            if (e.lengthSync() == 0) e.deleteSync();
          } else if (e.lastModifiedSync().isBefore(cutoff)) {
            e.deleteSync();
          }
        } catch (err) {
          debugPrint('TestImageStore cleanup: $err');
        }
      }
    } catch (e) {
      debugPrint('TestImageStore cleanup failed: $e');
    }
  }

  /// Where [url]'s image lives (whether or not it exists yet). Null until
  /// [init] has resolved the directory.
  File? _fileFor(String url) {
    final root = _root;
    if (root == null) return null;
    final name = sha256.convert(utf8.encode(url)).toString();
    return File(p.join(root.path, '$name.img'));
  }

  /// Paths already sniffed as real images this run (the renderer calls
  /// [cachedFile] on every build; the sniff reads from disk).
  final Set<String> _sniffed = {};

  /// The stored image for [url], synchronously, or null. Used by the renderer
  /// so a stored image shows on the very first frame. A file that is not an
  /// image (poisoned by an old build / disk damage) is deleted and reported
  /// as absent, so it gets downloaded again.
  File? cachedFile(String url) {
    try {
      final f = _fileFor(url);
      if (f == null || !f.existsSync() || f.lengthSync() <= 0) return null;
      if (_sniffed.contains(f.path)) return f;
      final raf = f.openSync();
      List<int> head;
      try {
        head = raf.readSync(_sniffBytes);
      } finally {
        raf.closeSync();
      }
      if (!looksLikeImage(head)) {
        debugPrint('TestImageStore: ${p.basename(f.path)} is not an image, '
            'deleting ($url)');
        f.deleteSync();
        return null;
      }
      _sniffed.add(f.path);
      return f;
    } catch (_) {
      return null;
    }
  }

  /// Drops the stored copy of [url] (e.g. it failed to decode), so the next
  /// download replaces it. Never throws.
  void evict(String url) {
    try {
      final f = _fileFor(url);
      if (f == null) return;
      _sniffed.remove(f.path);
      if (f.existsSync()) f.deleteSync();
    } catch (e) {
      debugPrint('TestImageStore.evict: $e');
    }
  }

  static const int _sniffBytes = 512;

  /// JPEG / PNG / GIF / WEBP magic bytes, or an `<svg` (optionally after a BOM,
  /// whitespace and an `<?xml` prolog). Anything else - HTML login pages, JSON
  /// errors - is not an image.
  @visibleForTesting
  static bool looksLikeImage(List<int> h) {
    bool at(int i, List<int> sig) {
      if (h.length < i + sig.length) return false;
      for (var k = 0; k < sig.length; k++) {
        if (h[i + k] != sig[k]) return false;
      }
      return true;
    }

    if (at(0, const [0xFF, 0xD8, 0xFF])) return true; // JPEG
    if (at(0, const [0x89, 0x50, 0x4E, 0x47])) return true; // PNG
    if (at(0, const [0x47, 0x49, 0x46, 0x38])) return true; // GIF8
    if (at(0, const [0x52, 0x49, 0x46, 0x46]) &&
        at(8, const [0x57, 0x45, 0x42, 0x50])) {
      return true; // RIFF....WEBP
    }
    var i = 0;
    if (at(0, const [0xEF, 0xBB, 0xBF])) i = 3;
    while (i < h.length && (h[i] == 0x20 || h[i] == 0x09 || h[i] == 0x0A || h[i] == 0x0D)) {
      i++;
    }
    final text = String.fromCharCodes(h.skip(i)).toLowerCase();
    if (text.startsWith('<svg')) return true;
    if (text.startsWith('<?xml') && text.contains('<svg')) return true;
    return false;
  }

  final Map<String, Future<StoreFetch>> _inFlight = {};

  /// A client error that retrying cannot fix (404, 410, 403, ...): the image is
  /// recorded as missing instead of failing the whole download. 408 / 429 are
  /// transient and, like every 5xx, stay errors.
  static bool isMissingStatus(int code) =>
      code >= 400 && code < 500 && code != 408 && code != 429;

  /// Downloads [url] into the store. Returns [StoreFetch.missing] for 4xx
  /// and throws on any other failure (network, timeout, bad status, empty or
  /// truncated body) — nothing partial is ever left under the final name.
  /// De-duplicated: concurrent callers (background prefetch, student-tap
  /// prepare) for the same url share ONE request.
  Future<StoreFetch> fetch(String url) {
    final running = _inFlight[url];
    if (running != null) return running;
    final f = _fetchNow(url);
    _inFlight[url] = f;
    f.then((_) => null, onError: (_) => null).whenComplete(() {
      if (identical(_inFlight[url], f)) _inFlight.remove(url);
    });
    return f;
  }

  Future<StoreFetch> _fetchNow(String url) async {
    final dest = _fileFor(url);
    if (dest == null) throw StateError('TestImageStore not initialised');
    final tmp =
        File('${dest.path}.${DateTime.now().microsecondsSinceEpoch}.tmp');
    // Aborts THIS request only (the client is shared by every in-flight
    // download, so it must never be closed on one transfer's timeout).
    final abort = Completer<void>();
    try {
      return await _download(url, dest, tmp, abort.future)
          .timeout(maxDuration);
    } on TimeoutException {
      // Stop the stalled transfer instead of letting it hold the socket.
      if (!abort.isCompleted) abort.complete();
      rethrow;
    } finally {
      try {
        if (tmp.existsSync()) tmp.deleteSync();
      } catch (e) {
        debugPrint('TestImageStore: temp cleanup failed: $e');
      }
    }
  }

  Future<StoreFetch> _download(
      String url, File dest, File tmp, Future<void> abortTrigger) async {
    final req = http.AbortableRequest('GET', Uri.parse(url),
        abortTrigger: abortTrigger)
      ..headers['User-Agent'] = 'AlochiMonitoring/1.0';
    final resp = await _client.send(req).timeout(timeout);
    if (isMissingStatus(resp.statusCode)) {
      await resp.stream.drain<void>().timeout(timeout);
      return StoreFetch.missing;
    }
    if (resp.statusCode != 200) {
      await resp.stream.drain<void>().timeout(timeout);
      throw HttpException('HTTP ${resp.statusCode}', uri: Uri.parse(url));
    }
    // Stream to disk; `Stream.timeout` fires on silence BETWEEN chunks, so
    // only a stalled connection is cut, not a slow one.
    final sink = tmp.openWrite();
    final head = <int>[];
    var length = 0;
    try {
      await for (final chunk in resp.stream.timeout(timeout)) {
        sink.add(chunk);
        length += chunk.length;
        if (head.length < _sniffBytes) {
          head.addAll(chunk.take(_sniffBytes - head.length));
        }
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    final expected = resp.contentLength;
    if (length == 0 || (expected != null && expected != length)) {
      throw HttpException('incomplete body ($length/$expected)',
          uri: Uri.parse(url));
    }
    if (!looksLikeImage(head)) {
      throw HttpException('response is not an image (${resp.headers['content-type']})',
          uri: Uri.parse(url));
    }
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
