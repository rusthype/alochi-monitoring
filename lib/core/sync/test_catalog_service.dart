// lib/core/sync/test_catalog_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../cache/image_cache_manager.dart';
import '../db/test_cache_db.dart';
import '../models/test_catalog.dart';

class TestCatalogService {
  TestCatalogService._();
  static final TestCatalogService instance = TestCatalogService._();

  /// Online yo'l: catalog'dan version solishtiradi; keshdan eski bo'lsa yuklab oladi va rasmlarni precache qiladi.
  /// Tarmoq xatosida keshdan qaytaradi.
  Future<Map<String, dynamic>?> ensureDownloaded(String testKey) async {
    try {
      final catalog = await api.getTestCatalog();
      TestCatalogEntry? entry;
      for (final e in catalog) {
        if (e.testKey == testKey) {
          entry = e;
          break;
        }
      }
      final serverVersion = entry?.version ?? 0;
      final cachedVer = await TestCacheDb.cachedVersion(testKey);

      if (cachedVer == null || cachedVer < serverVersion) {
        final detail = await api.getTestDetail(testKey);
        await TestCacheDb.put(testKey, serverVersion, detail);
        _precacheImages(detail);
        return detail;
      }
      return await TestCacheDb.get(testKey);
    } catch (e) {
      debugPrint('TestCatalogService.ensureDownloaded: tarmoq xatosi — keshdan qaytarildi ($e)');
      return TestCacheDb.get(testKey);
    }
  }

  /// Oflayn tezkor yo'l: faqat keshdan o'qiydi.
  Future<Map<String, dynamic>?> cached(String testKey) =>
      TestCacheDb.get(testKey);

  void _precacheImages(Map<String, dynamic> data) {
    final urls = _extractImageUrls(data);
    final manager = AlochiImageCacheManager();
    for (final url in urls) {
      final fixed = MonitoringApi.fixImageUrl(url);
      if (fixed.isEmpty) continue;
      unawaited(_downloadFile(manager, fixed));
    }
  }

  Future<void> _downloadFile(AlochiImageCacheManager manager, String url) async {
    try {
      await manager.downloadFile(url);
    } catch (_) {}
  }

  List<String> _extractImageUrls(dynamic data) {
    final urls = <String>[];
    if (data is Map) {
      for (final value in data.values) {
        urls.addAll(_extractImageUrls(value));
      }
    } else if (data is List) {
      for (final item in data) {
        urls.addAll(_extractImageUrls(item));
      }
    } else if (data is String && _looksLikeImageUrl(data)) {
      urls.add(data);
    }
    return urls;
  }

  bool _looksLikeImageUrl(String s) {
    if (s.isEmpty) return false;
    final lower = s.toLowerCase();
    return lower.contains('/media/') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif');
  }
}
