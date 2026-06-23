// lib/core/services/test_catalog_service.dart
import 'dart:convert';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../cache/image_cache_manager.dart';
import '../db/test_cache.dart';

/// Test katalog yozuvi holati.
enum CatalogStatus {
  /// Keshda bor, versiya bir xil — yangilash kerak emas.
  cached,

  /// Keshda bor, lekin yangi versiya bor — yangilash tavsiya etiladi.
  updatable,

  /// Hali yuklanmagan.
  notDownloaded,

  /// Offline holat: faqat keshdan ko'rsatiladi, internet yo'q.
  cachedOnly,
}

/// Katalog ro'yxat elementi — kichik model.
class CatalogEntry {
  final String testKey;
  final String title;
  final int grade;
  final int version;
  final CatalogStatus status;

  const CatalogEntry({
    required this.testKey,
    required this.title,
    required this.grade,
    required this.version,
    required this.status,
  });
}

/// Backend test katalogini boshqaradi: yuklash, kesh solishtirish, offline.
class TestCatalogService {
  final MonitoringApi _api;

  TestCatalogService(this._api);

  /// Katalogni yangilaydi va holat bilan CatalogEntry ro'yxatini qaytaradi.
  ///
  /// Online bo'lsa: backend'dan katalog olinadi, kesh bilan solishtiriladi.
  /// Offline bo'lsa: faqat keshdan cachedOnly holati bilan qaytaradi — crash yo'q.
  Future<List<CatalogEntry>> refresh() async {
    // Keshdan metadata olish — xato bo'lsa (masalan, web'da DB tayyor bo'lmasa)
    // bo'sh ro'yxat deb qaraymiz, fetch baribir davom etadi.
    List<Map<String, dynamic>> cachedRows;
    try {
      cachedRows = await TestCache.all();
    } catch (e) {
      debugPrint('TestCatalogService.refresh: cache read error: $e');
      cachedRows = [];
    }
    final cachedVersions = <String, int>{};
    for (final row in cachedRows) {
      final key = row['test_key']?.toString() ?? '';
      final ver = int.tryParse(row['version']?.toString() ?? '') ?? 0;
      if (key.isNotEmpty) cachedVersions[key] = ver;
    }

    // Backend'dan katalog — har doim to'g'ridan chaqiriladi, connectivity gate yo'q.
    // fetchTestCatalog() ichida try/catch bor — xato/timeout'da [] qaytaradi.
    final catalog = await _api.fetchTestCatalog();

    if (catalog.isEmpty) {
      // Fetch hech narsa bermadi — keshga qaytamiz.
      // "Internet kerak" faqat kesh ham bo'sh bo'lsa ko'rsatiladi.
      if (cachedRows.isEmpty) return [];
      return cachedRows.map((row) {
        final key = row['test_key']?.toString() ?? '';
        final title = row['title']?.toString() ?? '';
        final grade = int.tryParse(row['grade']?.toString() ?? '') ?? 0;
        final version = int.tryParse(row['version']?.toString() ?? '') ?? 0;
        return CatalogEntry(
          testKey: key,
          title: title,
          grade: grade,
          version: version,
          status: CatalogStatus.cachedOnly,
        );
      }).toList();
    }

    // Online: backend katalogi bilan keshni solishtir
    final entries = <CatalogEntry>[];
    for (final item in catalog) {
      final key = item['test_key']?.toString() ?? '';
      if (key.isEmpty) continue;
      final title = item['title']?.toString() ?? '';
      final grade = int.tryParse(item['grade']?.toString() ?? '') ?? 0;
      final version = int.tryParse(item['version']?.toString() ?? '') ?? 0;

      final cachedVer = cachedVersions[key];
      final CatalogStatus status;
      if (cachedVer == null) {
        status = CatalogStatus.notDownloaded;
      } else if (version > cachedVer) {
        status = CatalogStatus.updatable;
      } else {
        status = CatalogStatus.cached;
      }

      entries.add(CatalogEntry(
        testKey: key,
        title: title,
        grade: grade,
        version: version,
        status: status,
      ));
    }
    return entries;
  }

  /// Testni backend'dan yuklab keshga saqlaydi va rasmlarni prefetch qiladi.
  ///
  /// Bittasi xato bo'lsa ham davom etadi (best-effort).
  /// Muvaffaqiyatli kesh'ga yozilsa — true, aks holda false qaytaradi.
  Future<bool> download(String testKey) async {
    try {
      final data = await _api.fetchTest(testKey);
      if (data == null) {
        debugPrint('TestCatalogService.download($testKey): null response');
        return false;
      }

      final title = data['title']?.toString() ?? '';
      final grade = int.tryParse(data['grade']?.toString() ?? '') ?? 0;
      final version = int.tryParse(data['version']?.toString() ?? '') ?? 0;
      final jsonStr = jsonEncode(data);

      await TestCache.upsert(testKey, title, grade, version, jsonStr);

      // Rasmlarni prefetch — best-effort, xato bo'lsa davom etamiz
      _prefetchImages(data);

      return true;
    } catch (e) {
      debugPrint('TestCatalogService.download($testKey) error: $e');
      return false;
    }
  }

  /// test_data ichidagi barcha http bilan boshlanadigan rasm url'larni
  /// AlochiImageCacheManager orqali prefetch qiladi.
  void _prefetchImages(Map<String, dynamic> data) {
    final urls = _collectImageUrls(data);
    if (urls.isEmpty) return;
    final cacheManager = AlochiImageCacheManager();
    for (final url in urls) {
      if (url.isEmpty) continue;
      cacheManager.downloadFile(url).then((_) {
        // muvaffaqiyatli kesh'landi
      }).catchError((Object e) {
        debugPrint('Image prefetch failed for $url: $e');
      });
    }
  }

  /// Rekursiv tarzda JSON ichidan barcha http/https boshlanadigan string'larni yig'adi.
  List<String> _collectImageUrls(dynamic node) {
    if (node is String) {
      if (node.startsWith('http://') || node.startsWith('https://')) {
        return [node];
      }
      return [];
    }
    if (node is List) {
      final urls = <String>[];
      for (final item in node) {
        urls.addAll(_collectImageUrls(item));
      }
      return urls;
    }
    if (node is Map) {
      final urls = <String>[];
      for (final value in node.values) {
        urls.addAll(_collectImageUrls(value));
      }
      return urls;
    }
    return [];
  }
}

/// Global singleton
final testCatalogService = TestCatalogService(api);
