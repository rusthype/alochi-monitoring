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

  /// Backend'dagi so'nggi yangilanish vaqti — katalog ro'yxatlarini
  /// yangi-birinchi tartiblash uchun (null bo'lsa eskirgan/noma'lum deb
  /// hisoblanadi va oxiriga tushadi).
  final DateTime? updatedAt;

  /// Vaqt-oyna oxiri: [lockedUntil] bilan birga bo'lsa, test faqat
  /// [lockedUntil]..[availableUntil] oralig'ida ochiq bo'ladi (TASK: test
  /// availability window badge). Null bo'lsa — cheksiz ochiq (eski,
  /// bir-nuqtali qulf xatti-harakati o'zgarishsiz qoladi).
  final DateTime? availableUntil;

  /// Test backend'da qachon yaratilgan — "NEW"/"Yangi" badge uchun
  /// ([isNew]). Backend har doim jo'natadi, lekin eski/undeployed
  /// backend bilan ham crash bo'lmasligi uchun null-safe parse qilinadi.
  final DateTime? createdAt;

  /// [isNew] uchun chegara — shundan yosh testlar "NEW" deb hisoblanadi.
  static const Duration _newThreshold = Duration(days: 3);

  /// Test so'nggi [_newThreshold] ichida yaratilganmi.
  bool get isNew =>
      createdAt != null && DateTime.now().difference(createdAt!) < _newThreshold;

  const CatalogEntry({
    required this.testKey,
    required this.title,
    required this.grade,
    required this.version,
    required this.status,
    this.schoolButtons = const [],
    this.runnerType = 'engine',
    this.lockedUntil,
    this.updatedAt,
    this.availableUntil,
    this.createdAt,
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

  static DateTime? lockedUntilFor(String testKey) => _lockedUntilCache[testKey];

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
  ///
  /// `schoolCode` — berilsa, so'rovchi maktabni backendga bildiradi;
  /// maktabga bog'langan (school FK bor) testlarni ko'rish uchun SHART
  /// (groupId bilan birga, GroupSelectScreen).
  Future<List<CatalogEntry>> refresh(
      {String? groupId, String? schoolCode}) async {
    // Keshdan metadata olish (har doim holda kerak)
    final cachedRows = await TestCache.all();
    final cachedVersions = <String, int>{};
    for (final row in cachedRows) {
      final key = row['test_key']?.toString() ?? '';
      final ver = int.tryParse(row['version']?.toString() ?? '') ?? 0;
      if (key.isNotEmpty) cachedVersions[key] = ver;
    }

    // Online urinish
    List<Map<String, dynamic>> catalog;
    bool fetchFailed;
    try {
      catalog =
          await _api.fetchTestCatalog(groupId: groupId, schoolCode: schoolCode);
      fetchFailed = false;
    } catch (e) {
      debugPrint('TestCatalogService.refresh: network error: $e');
      catalog = [];
      fetchFailed = true;
    }

    if (fetchFailed) {
      // Tarmoq xatosi — faqat keshdan ko'rsat
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
      final lockedUntil =
          (lockedUntilRaw is String && lockedUntilRaw.isNotEmpty)
              ? DateTime.tryParse(lockedUntilRaw)
              : null;
      _lockedUntilCache[key] = lockedUntil;

      final availableUntilRaw = item['available_until'];
      final availableUntil =
          (availableUntilRaw is String && availableUntilRaw.isNotEmpty)
              ? DateTime.tryParse(availableUntilRaw)
              : null;

      entries.add(CatalogEntry(
        testKey: key,
        title: title,
        grade: grade,
        version: version,
        status: status,
        schoolButtons: schoolButtons,
        runnerType: item['runner_type']?.toString() ?? 'engine',
        lockedUntil: lockedUntil,
        updatedAt: DateTime.tryParse(item['updated_at']?.toString() ?? ''),
        availableUntil: availableUntil,
        createdAt: DateTime.tryParse(item['created_at']?.toString() ?? ''),
      ));
    }

    // Muvaffaqiyatli fetch — backend katalogida endi yo'q (masalan
    // arxivlangan) testlarni keshdan tozalaymiz, best-effort (asosiy
    // natijani bloklamasin).
    try {
      await TestCache.pruneNotIn(entries.map((e) => e.testKey).toSet());
    } catch (e) {
      debugPrint('TestCatalogService.refresh: cache prune error: $e');
    }

    return entries;
  }

  /// Testni backend'dan yuklab keshga saqlaydi va rasmlarni prefetch qiladi.
  ///
  /// Bittasi xato bo'lsa ham davom etadi (best-effort).
  /// Muvaffaqiyatli kesh'ga yozilsa — true, aks holda false qaytaradi.
  ///
  /// `groupId` — tanlangan guruh ma'lum bo'lganda (yangi maktab→guruh→test
  /// oqimi, GroupSelectScreen) uzatiladi, detail fetch'ga qo'shiladi
  /// (S-001: guruh scoping xavfsizlik chegarasi). Guruhsiz maktab yoki
  /// eski (guruhdan tashqari) yuklash oqimlarida berilmaydi — orqaga moslik.
  ///
  /// `schoolCode` — tanlangan maktab kodi ma'lum bo'lganda uzatiladi;
  /// maktabga bog'langan testni yuklash uchun SHART (groupId bilan birga).
  Future<bool> download(String testKey,
      {String? groupId, String? schoolCode}) async {
    try {
      final data = await _api.fetchTest(testKey,
          groupId: groupId, schoolCode: schoolCode);
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
      final lower = node.toLowerCase();
      if (node.startsWith('/') &&
          (lower.endsWith('.png') ||
              lower.endsWith('.jpg') ||
              lower.endsWith('.jpeg') ||
              lower.endsWith('.gif') ||
              lower.endsWith('.webp') ||
              lower.endsWith('.svg'))) {
        return [MonitoringApi.fixImageUrl(node)];
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
