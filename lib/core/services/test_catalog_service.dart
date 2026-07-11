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

/// Maktab tugmasi — catalog'dan keladi.
class SchoolButton {
  final String pin;
  final String label;
  final String schoolCode;
  final bool randomVariant;

  const SchoolButton({
    required this.pin,
    required this.label,
    required this.schoolCode,
    required this.randomVariant,
  });

  factory SchoolButton.fromJson(Map<String, dynamic> j) => SchoolButton(
        pin: j['pin']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        schoolCode: j['school_code']?.toString() ?? '',
        randomVariant: j['random_variant'] == true,
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
  final String runnerType;

  /// Vaqt-qulf: null = qulflanmagan. Kelajakdagi vaqt bo'lsa, test
  /// oldindan yuklab olinishi mumkin, lekin ochilmaydi (TASK 08d).
  final DateTime? lockedUntil;

  const CatalogEntry({
    required this.testKey,
    required this.title,
    required this.grade,
    required this.version,
    required this.status,
    this.schoolButtons = const [],
    this.runnerType = 'engine',
    this.lockedUntil,
  });
}

/// Backend test katalogini boshqaradi: yuklash, kesh solishtirish, offline.
class TestCatalogService {
  final MonitoringApi _api;

  TestCatalogService(this._api);

  /// Last known `locked_until` per test_key from the most recent refresh().
  /// Used by runner_dispatch.dart as a second, defense-in-depth lock check
  /// (the primary gate lives in the catalog UI — login_screen.dart) in case
  /// launchRunner is ever reached through a path other than that UI.
  static final Map<String, DateTime?> _lockedUntilCache = {};

  static DateTime? lockedUntilFor(String testKey) =>
      _lockedUntilCache[testKey];

  /// Katalogni yangilaydi va holat bilan CatalogEntry ro'yxatini qaytaradi.
  ///
  /// Online bo'lsa: backend'dan katalog olinadi, kesh bilan solishtiriladi.
  /// Offline bo'lsa: faqat keshdan cachedOnly holati bilan qaytaradi — crash yo'q.
  ///
  /// `groupId` — berilsa, faqat shu guruhga bog'langan (yoki guruhsiz)
  /// testlar qaytadi (guruh oqimi, GroupSelectScreen). Guruh o'zgarganda
  /// chaqiruvchi shu metodni YANGI groupId bilan qayta chaqirishi kerak —
  /// bu yerda natija keshlanmaydi, har chaqiriq tarmoqdan yangi olinadi
  /// (kesh invalidatsiyasi shu tarzda ta'minlanadi).
  Future<List<CatalogEntry>> refresh({String? groupId}) async {
    // Keshdan metadata olish (har todo holda kerak)
    final cachedRows = await TestCache.all();
    final cachedVersions = <String, int>{};
    for (final row in cachedRows) {
      final key = row['test_key']?.toString() ?? '';
      final ver = int.tryParse(row['version']?.toString() ?? '') ?? 0;
      if (key.isNotEmpty) cachedVersions[key] = ver;
    }

    // Online urinish
    List<Map<String, dynamic>> catalog;
    try {
      catalog = await _api.fetchTestCatalog(groupId: groupId);
    } catch (e) {
      debugPrint('TestCatalogService.refresh: network error: $e');
      catalog = [];
    }

    if (catalog.isEmpty) {
      // Offline yoki katalog bo'sh — faqat keshdan ko'rsat
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

      final rawButtons = item['school_buttons'];
      final schoolButtons = (rawButtons is List)
          ? rawButtons
              .whereType<Map<String, dynamic>>()
              .map(SchoolButton.fromJson)
              .toList()
          : <SchoolButton>[];

      final lockedUntilRaw = item['locked_until'];
      final lockedUntil = (lockedUntilRaw is String && lockedUntilRaw.isNotEmpty)
          ? DateTime.tryParse(lockedUntilRaw)
          : null;
      _lockedUntilCache[key] = lockedUntil;

      entries.add(CatalogEntry(
        testKey: key,
        title: title,
        grade: grade,
        version: version,
        status: status,
        schoolButtons: schoolButtons,
        runnerType: item['runner_type']?.toString() ?? 'engine',
        lockedUntil: lockedUntil,
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
