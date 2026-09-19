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
/// style string values that look like an http(s) URL.
List<String> collectDiagnosticImageUrls(dynamic node) {
  if (node is String) {
    return node.startsWith('http://') || node.startsWith('https://')
        ? [node]
        : const [];
  }
  if (node is List) return node.expand(collectDiagnosticImageUrls).toList();
  if (node is Map) {
    return node.values.expand(collectDiagnosticImageUrls).toList();
  }
  return const [];
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
