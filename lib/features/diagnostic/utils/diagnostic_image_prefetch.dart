// lib/features/diagnostic/utils/diagnostic_image_prefetch.dart
//
// Single shared question-image cache warm-up used by BOTH
// diagnostic_test_runner_screen.dart (mid-test next-subject prefetch) and
// diagnostic_student_select_screen.dart (student-tap prefetch, before the
// runner screen even exists) — extracted so there is exactly one
// URL-normalization + cache-manager call pattern instead of two copies
// drifting apart.
import 'package:flutter/foundation.dart';
import '../../../core/api/api_client.dart' show MonitoringApi;
import '../../../core/offline/offline_media.dart';
import '../../../core/cache/image_cache_manager.dart';

/// Walks a (possibly nested) question map/list for `image_url`/`svg_visual`-
/// style string values that look like an image URL — absolute (`http(s)://`,
/// `//`) OR relative (`/media/...`, `media/...`, or any string ending in a
/// known image extension) — and returns them already fixed via
/// `MonitoringApi.fixImageUrl`, so callers never need to re-map. Root-cause
/// fix for diagnostic-image-eternal-spinner: relative URLs used to be
/// silently dropped here, before `fixImageUrl` ever saw them.
List<String> collectDiagnosticImageUrls(dynamic node) {
  final urls = <String>{};

  void extract(dynamic current) {
    if (current is String) {
      final s = current.trim();
      if (s.isEmpty) return;
      final looksLikeImage = s.startsWith('http://') ||
          s.startsWith('https://') ||
          s.startsWith('//') ||
          s.startsWith('/media/') ||
          s.startsWith('media/') ||
          RegExp(r'\.(png|jpe?g|webp|gif|svg)(\?.*)?$', caseSensitive: false)
              .hasMatch(s);
      if (!looksLikeImage) return;
      // Offline USB pack image: already a file on disk, nothing to download.
      if (OfflineMedia.fileFor(s) != null) return;
      final fixed = MonitoringApi.fixImageUrl(s);
      if (fixed.isNotEmpty) urls.add(fixed);
      return;
    }
    if (current is List) {
      for (final item in current) {
        extract(item);
      }
    } else if (current is Map) {
      for (final value in current.values) {
        extract(value);
      }
    }
  }

  extract(node);
  return urls.toList();
}

/// Downloads one image into the shared cache; injectable for tests.
typedef DiagnosticImageDownloader = Future<void> Function(String url);

// getSingleFile = cache hit when fresh (no network), download otherwise —
// unlike downloadFile, which re-requests even when the file is cached.
Future<void> _cacheDownload(String url) =>
    AlochiImageCacheManager().getSingleFile(url);

/// Ordered, bounded image prefetch: URLs are fetched in question order with at
/// most [concurrency] in flight, so the first questions' images land first
/// instead of competing with the whole package. Best-effort: failures are
/// logged, never thrown. Callers may ignore the returned future (fire and
/// forget) or await it.
Future<void> prefetchDiagnosticImages(
  List<Map<String, dynamic>> questions, {
  DiagnosticImageDownloader? download,
  int concurrency = 3,
}) async {
  final fetch = download ?? _cacheDownload;
  // Must match the exact key AppNetworkImage/CachedNetworkImage renders with
  // (MonitoringApi.fixImageUrl(url)) — collectDiagnosticImageUrls already
  // returns fixed URLs. Insertion order = question order.
  final urls = <String>{
    for (final q in questions) ...collectDiagnosticImageUrls(q),
  }.toList();
  var next = 0;
  Future<void> worker() async {
    while (next < urls.length) {
      final url = urls[next++];
      try {
        await fetch(url);
      } catch (e) {
        debugPrint('Diagnostic image prefetch failed for $url: $e');
      }
    }
  }

  await Future.wait(List.generate(concurrency, (_) => worker()));
}

/// Waits (at most [timeout], never throws) until [question]'s image(s) are in
/// the cache, so the question's first render is a cache hit instead of a
/// spinner. A slow/offline/broken image just lets the reveal proceed.
Future<void> awaitDiagnosticQuestionImages(
  Map<String, dynamic>? question, {
  Duration timeout = const Duration(seconds: 4),
  DiagnosticImageDownloader? download,
}) async {
  if (question == null) return;
  final urls = collectDiagnosticImageUrls(question);
  if (urls.isEmpty) return;
  final fetch = download ?? _cacheDownload;
  try {
    await Future.wait(
      urls.map((u) => fetch(u).catchError((Object _) {})),
    ).timeout(timeout);
  } catch (_) {
    // Timed out / failed — best-effort, reveal anyway.
  }
}
