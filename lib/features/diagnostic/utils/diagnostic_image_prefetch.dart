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

/// Best-effort, fire-and-forget image prefetch for a batch of questions —
/// same pattern as `TestCatalogService._prefetchImages` (monitoring).
void prefetchDiagnosticImages(List<Map<String, dynamic>> questions) {
  final cacheManager = AlochiImageCacheManager();
  for (final q in questions) {
    for (final rawUrl in collectDiagnosticImageUrls(q)) {
      // Must match the exact key AppNetworkImage/CachedNetworkImage renders
      // with (MonitoringApi.fixImageUrl(url)) — prefetching the raw url
      // writes a cache entry the renderer never looks up.
      final url = MonitoringApi.fixImageUrl(rawUrl);
      if (url.isEmpty) continue;
      cacheManager.downloadFile(url).then((_) {}).catchError((Object e) {
        debugPrint('Diagnostic image prefetch failed for $url: $e');
      });
    }
  }
}
