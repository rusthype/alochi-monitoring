// lib/core/sync/test_catalog_service.dart
import 'dart:async';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../db/test_cache_db.dart';
import '../models/test_catalog.dart';
import '../services/test_catalog_service.dart' as engine;

/// Legacy (guest-flow) cache: unit1 / bob1_4 / math_gN loaders. Images go
/// through the SAME readiness gate the engine uses
/// ([engine.TestCatalogService.ensureTestImages] -> persistent TestImageStore),
/// not a fire-and-forget precache.
class TestCatalogService {
  TestCatalogService._()
      : _apiOf = (() => api),
        _imagesOf = (() => engine.testCatalogService);
  static final TestCatalogService instance = TestCatalogService._();

  @visibleForTesting
  TestCatalogService.forTest(this._apiOf, this._imagesOf);

  final MonitoringApi Function() _apiOf;
  final engine.TestCatalogService Function() _imagesOf;

  /// How long a loader waits for the images; the download itself keeps going
  /// in the background past this and fills the store for the next run.
  static const _imageWait = Duration(seconds: 60);

  /// Online yo'l: catalog'dan version solishtiradi; keshdan eski bo'lsa yuklab oladi.
  /// Versiya keshga FAQAT rasmlari do'konga to'liq tushgandan keyin yoziladi
  /// (aks holda keyingi ishga tushishda qayta uriniladi).
  /// Tarmoq xatosida keshdan qaytaradi.
  Future<Map<String, dynamic>?> ensureDownloaded(String testKey) async {
    try {
      final catalog = await _apiOf().getTestCatalog();
      TestCatalogEntry? entry;
      for (final e in catalog) {
        if (e.testKey == testKey) {
          entry = e;
          break;
        }
      }
      final serverVersion = entry?.version ?? 0;
      final cachedVer = await TestCacheDb.cachedVersion(testKey);
      // A row that no longer decodes comes back null (and is dropped).
      final cached = cachedVer == null ? null : await TestCacheDb.get(testKey);

      if (cached == null || cachedVer == null || cachedVer < serverVersion) {
        final detail = await _apiOf().getTestDetail(testKey);
        if (await _imagesReady(testKey, detail)) {
          await TestCacheDb.put(testKey, serverVersion, detail);
        }
        return detail;
      }
      await _imagesReady(testKey, cached); // top-up only; data is returned anyway
      return cached;
    } catch (e) {
      debugPrint('TestCatalogService.ensureDownloaded: tarmoq xatosi — keshdan qaytarildi ($e)');
      return TestCacheDb.get(testKey);
    }
  }

  /// Oflayn tezkor yo'l: faqat keshdan o'qiydi.
  Future<Map<String, dynamic>?> cached(String testKey) =>
      TestCacheDb.get(testKey);

  Future<bool> _imagesReady(String testKey, Map<String, dynamic> data) async {
    try {
      final ok = await _imagesOf().ensureTestImages(data).timeout(_imageWait);
      if (!ok) debugPrint('TestCatalogService($testKey): images incomplete');
      return ok;
    } catch (e) {
      debugPrint('TestCatalogService($testKey): image gate failed: $e');
      return false;
    }
  }
}
