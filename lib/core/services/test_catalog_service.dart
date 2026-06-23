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

/// Maktab tugmasi konfiguratsiyasi — catalog LIST javobidan keladi.
class SchoolButton {
  final String label;
  final String schoolCode;
  final bool randomVariant;
  final String? pin;

  const SchoolButton({
    required this.label,
    required this.schoolCode,
    required this.randomVariant,
    this.pin,
  });

  factory SchoolButton.fromJson(Map<String, dynamic> j) => SchoolButton(
        label: j['label']?.toString() ?? '',
        schoolCode: j['school_code']?.toString() ?? '',
        randomVariant: j['random_variant'] == true,
        pin: j['pin']?.toString(),
      );
}

/// Katalog ro'yxat elementi — kichik model.
class CatalogEntry {
  final String testKey;
  final String title;
  final int grade;
  final int version;
  final CatalogStatus status;
  final List<SchoolButton> schoolButtons;

  const CatalogEntry({
    required this.testKey,
    required this.title,
    required this.grade,
    required this.version,
    required this.status,
    this.schoolButtons = const [],
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
      final futures = cachedRows.map((row) async {
        final key = row['test_key']?.toString() ?? '';
        final schoolButtons = await _parseSchoolButtonsFromCache(key);
        return CatalogEntry(
          testKey: key,
          title: row['title']?.toString() ?? '',
          grade: int.tryParse(row['grade']?.toString() ?? '') ?? 0,
          version: int.tryParse(row['version']?.toString() ?? '') ?? 0,
          status: CatalogStatus.cachedOnly,
          schoolButtons: schoolButtons,
        );
      });
      return Future.wait(futures);
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

      final rawButtons = item['school_buttons'];
      final schoolButtons = <SchoolButton>[];
      if (rawButtons is List) {
        for (final btn in rawButtons) {
          if (btn is! Map) continue;
          final b = SchoolButton.fromJson(Map<String, dynamic>.from(btn));
          if (b.label.isEmpty || b.schoolCode.isEmpty) continue;
          schoolButtons.add(b);
        }
      }

      entries.add(CatalogEntry(
        testKey: key,
        title: title,
        grade: grade,
        version: version,
        status: status,
        schoolButtons: schoolButtons,
      ));
    }
    return entries;
  }

  /// Keshdan school_buttons o'qib parse qiladi (offline rejim uchun fallback).
  Future<List<SchoolButton>> _parseSchoolButtonsFromCache(
      String testKey) async {
    try {
      final testData = await TestCache.get(testKey);
      if (testData == null) return const [];
      final raw = testData['school_buttons'];
      if (raw is! List || raw.isEmpty) return const [];
      final buttons = <SchoolButton>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final b =
            SchoolButton.fromJson(Map<String, dynamic>.from(item));
        if (b.label.isEmpty || b.schoolCode.isEmpty) continue;
        buttons.add(b);
      }
      return buttons;
    } catch (e) {
      return const [];
    }
  }

  /// Testni backend'dan yuklab keshga saqlaydi va rasmlarni prefetch qiladi.
  ///
  /// [onProgress] har qadam (json=1, har rasm=1) tugaganda chaqiriladi.
  /// total = 1 + urls.length; done 1..total.
  /// Muvaffaqiyatli kesh'ga yozilsa — true, aks holda false qaytaradi.
  Future<bool> download(
    String testKey, {
    void Function(int done, int total)? onProgress,
  }) async {
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

      final urls = _collectImageUrls(data);
      final total = 1 + urls.length;
      onProgress?.call(1, total);

      await _prefetchImages(urls,
          done: 1, total: total, onProgress: onProgress);

      return true;
    } catch (e) {
      debugPrint('TestCatalogService.download($testKey) error: $e');
      return false;
    }
  }

  /// Rasm URL'larini AlochiImageCacheManager orqali birin-ketin prefetch qiladi.
  /// Best-effort: har rasm xato bo'lsa ham done++ va onProgress chaqiriladi.
  Future<void> _prefetchImages(
    List<String> urls, {
    required int done,
    required int total,
    void Function(int done, int total)? onProgress,
  }) async {
    if (urls.isEmpty) return;
    final cacheManager = AlochiImageCacheManager();
    var d = done;
    for (final url in urls) {
      if (url.isNotEmpty) {
        try {
          await cacheManager.downloadFile(url);
        } catch (e) {
          debugPrint('Image prefetch failed for $url: $e');
        }
      }
      d++;
      onProgress?.call(d, total);
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
