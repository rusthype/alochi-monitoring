// lib/core/services/test_catalog_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../cache/test_image_store.dart';
import '../db/attempt_store.dart';
import '../db/test_cache.dart';
import '../models/test_version.dart';
import '../diagnostics/active_test_gate.dart';
import 'heartbeat_service.dart';
import 'server_clock.dart';
import '../offline/lan_client_session.dart' show isOfflineModeOpen;

/// The `variants` key the engine actually renders for [variant]: the exact key
/// when present, else the numerically nearest numeric key, else the first one
/// (null for an empty map). Mirrors `TestSpec._fallbackVariant` in
/// engine/test_models.dart (private there) so the readiness gate checks the
/// SAME variant's images the student will see.
// ponytail: test_models.dart should call this instead of keeping its own copy.
String? effectiveVariantKey(Map<dynamic, dynamic> variants, int variant) {
  if (variants.isEmpty) return null;
  final want = variant.toString();
  if (variants[want] != null) return want;
  final keys = variants.keys.map((k) => k.toString()).toList();
  final numeric = keys.where((k) => int.tryParse(k) != null);
  var best = keys.first;
  if (numeric.isNotEmpty) {
    best = numeric.reduce((a, b) =>
        (int.parse(a) - variant).abs() <= (int.parse(b) - variant).abs()
            ? a
            : b);
  }
  return best;
}

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
  // Haqiqiy unikal maktab identifikatori (School.id, UUID) — school_code
  // (School.number) tuman ichida takrorlanishi mumkin (masalan bir nechta
  // tumanda "39-maktab"), schoolId esa kolliziyasiz. Eski backend hali
  // yubormasa bo'sh string ('') qaytadi — chaqiruvchilar shu holda
  // schoolCode'ga qaytadi (orqaga moslik).
  final String schoolId;
  final bool randomVariant;

  const SchoolButton({
    required this.pin,
    required this.label,
    required this.schoolCode,
    this.schoolId = '',
    required this.randomVariant,
  });

  factory SchoolButton.fromJson(Map<String, dynamic> j) => SchoolButton(
        pin: j['pin']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        schoolCode: j['school_code']?.toString() ?? '',
        schoolId: j['school_id']?.toString() ?? '',
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
      createdAt != null &&
      DateTime.now().difference(createdAt!) < _newThreshold;

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
  final MonitoringApi Function() _apiOf;
  final TestImageStore? _storeOverride;
  final Duration _retryDelay;
  final Duration Function() _bgJitter;
  final List<Duration> _bgBackoff;
  final Duration _bgYield;

  static Duration _randomJitter() =>
      Duration(milliseconds: math.Random().nextInt(8000));

  /// `store` / `retryDelay` are injectable for tests only; production uses
  /// the process-wide [TestImageStore.instance] (the SAME store the renderer
  /// [AppNetworkImage] reads from).
  TestCatalogService(MonitoringApi api,
      {TestImageStore? store,
      Duration retryDelay = const Duration(milliseconds: 400),
      Duration Function()? bgJitter,
      List<Duration> bgBackoff = const [
        Duration(seconds: 2),
        Duration(seconds: 8),
        Duration(seconds: 30),
      ],
      Duration bgYield = const Duration(milliseconds: 500)})
      : _apiOf = (() => api),
        _storeOverride = store,
        _retryDelay = retryDelay,
        _bgJitter = bgJitter ?? _randomJitter,
        _bgBackoff = bgBackoff,
        _bgYield = bgYield;

  /// Resolves the API on every call — the global `api` can be swapped for an
  /// offline-pack implementation at runtime.
  TestCatalogService.dynamic(this._apiOf,
      {TestImageStore? store,
      Duration retryDelay = const Duration(milliseconds: 400),
      Duration Function()? bgJitter,
      List<Duration> bgBackoff = const [
        Duration(seconds: 2),
        Duration(seconds: 8),
        Duration(seconds: 30),
      ],
      Duration bgYield = const Duration(milliseconds: 500)})
      : _storeOverride = store,
        _retryDelay = retryDelay,
        _bgJitter = bgJitter ?? _randomJitter,
        _bgBackoff = bgBackoff,
        _bgYield = bgYield;

  TestImageStore get _store => _storeOverride ?? TestImageStore.instance;

  MonitoringApi get _api => _apiOf();

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
  ///
  /// `schoolId` — berilsa, `schoolCode`dan ustunlik oladi: bir xil raqamli
  /// (masalan "39") bir nechta maktab bo'lganda backend aynan shu maktabni
  /// kolliziyasiz aniqlaydi (2026-09-07, School.number unikal emasligi
  /// muammosi).
  Future<List<CatalogEntry>> refresh(
      {String? groupId, String? schoolCode, String? schoolId}) async {
    // The lock checks that follow use server time (persisted offset).
    await ServerClock.ensureLoaded();
    // Keshdan metadata olish (har doim holda kerak). A broken cache DB must
    // never break the catalog: TestCache quarantines a corrupt file itself,
    // anything else is treated as "nothing cached".
    List<Map<String, dynamic>> cachedRows;
    try {
      cachedRows = await TestCache.all();
    } catch (e) {
      debugPrint('TestCatalogService.refresh: cache unreadable: $e');
      cachedRows = [];
    }
    final unfiltered = _blank(groupId) && _blank(schoolCode) && _blank(schoolId);
    final cachedVersions = <String, int>{};
    for (final row in cachedRows) {
      final key = row['test_key']?.toString() ?? '';
      final ver = parseTestVersion(row['version']);
      if (key.isNotEmpty) cachedVersions[key] = ver;
    }

    // Online urinish
    List<Map<String, dynamic>> catalog;
    bool fetchFailed;
    Object? fetchError;
    try {
      catalog = await _api.fetchTestCatalog(
          groupId: groupId, schoolCode: schoolCode, schoolId: schoolId);
      fetchFailed = false;
    } catch (e) {
      debugPrint('TestCatalogService.refresh: network error: $e');
      catalog = [];
      fetchFailed = true;
      fetchError = e;
    }

    if (fetchFailed) {
      // Tarmoq xatosi — faqat keshdan ko'rsat. Lekin keshda HECH narsa yo'q
      // bo'lsa, bu "chindan ham bo'sh" degani emas — masalan 429/timeout
      // (2026-08-25: guruh tanlashda throttle 429'i xuddi shu yo'l bilan
      // "Bu guruh uchun test topilmadi"ga aylanib qolgan, guruh o'zgarib
      // qaytilganda tasodifan tuzalgandek ko'ringan). Chaqiruvchi (masalan
      // GroupSelectScreen._selectGroup) buni ochiq xato holati sifatida
      // ko'rsatib, qayta urinish imkonini bersin — jim tarzda bo'sh ro'yxat
      // qaytarish o'rniga.
      // Offline the list is scoped like the online one: only the tests that
      // were listed for this group / school (or globally), with their last
      // known time lock. Rows cached before scoping existed stay visible.
      final visible = cachedRows
          .where((row) => visibleInScope(row['scopes'] as Set<String>?,
              groupId: groupId, schoolCode: schoolCode, schoolId: schoolId))
          .toList();
      if (visible.isEmpty) {
        throw fetchError ?? Exception('catalog fetch failed');
      }
      return visible.map((row) {
        final key = row['test_key']?.toString() ?? '';
        final title = row['title']?.toString() ?? '';
        final grade = int.tryParse(row['grade']?.toString() ?? '') ?? 0;
        final version = parseTestVersion(row['version']);
        final lockedUntil = _parseTime(row['locked_until']);
        _lockedUntilCache[key] = lockedUntil;
        return CatalogEntry(
          testKey: key,
          title: title,
          grade: grade,
          version: version,
          status: CatalogStatus.cachedOnly,
          lockedUntil: lockedUntil,
          availableUntil: _parseTime(row['available_until']),
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
      final version = parseTestVersion(item['version']);

      var cachedVer = cachedVersions[key];
      // A row whose JSON cannot be read back is not a downloaded test.
      if (cachedVer != null && !await _readable(key, cachedVer)) {
        cachedVer = null;
      }
      final CatalogStatus status;
      if (isOfflineModeOpen && (cachedVer == null || version > cachedVer)) {
        // USB pack / LAN client: the content comes from the pack itself, so
        // copy it into the cache now (what the "Скачать" button did by hand).
        // Only a real copy reports `cached`; a failure stays visible as the
        // normal not-downloaded / updatable state with its button.
        final ok = await download(key,
            groupId: groupId, schoolCode: schoolCode, schoolId: schoolId);
        if (ok) {
          status = CatalogStatus.cached;
        } else {
          status = cachedVer == null
              ? CatalogStatus.notDownloaded
              : CatalogStatus.updatable;
        }
      } else if (cachedVer == null) {
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

      // Remember the lock and the scope for the offline list (cached tests
      // only; the pack/LAN memory cache ignores it).
      if (cachedVer != null && !isOfflineModeOpen) {
        await TestCache.recordListing(key,
            scope: scopeToken(
                groupId: groupId, schoolCode: schoolCode, schoolId: schoolId),
            updateLock: true,
            lockedUntil: lockedUntilRaw is String ? lockedUntilRaw : null,
            availableUntil:
                availableUntilRaw is String ? availableUntilRaw : null);
      }

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
    // natijani bloklamasin). FAQAT filtrsiz (maktab/guruh berilmagan) so'rov:
    // filtrlangan katalog boshqa guruh/maktab testlarini yashiradi. Qarang
    // [_pruneStale].
    if (unfiltered && !isOfflineModeOpen) {
      try {
        final keep = entries.map((e) => e.testKey).toSet();
        await _tagGlobal(keep.where(cachedVersions.containsKey));
        final removed = await _pruneStale(keep, cachedVersions.keys);
        if (removed > 0) unawaited(gcStore());
      } catch (e) {
        debugPrint('TestCatalogService.refresh: cache prune error: $e');
      }
    }

    // Heal: cached tests whose images are incomplete get a background top-up.
    unawaited(healIncompleteTests());

    return entries;
  }

  static bool _blank(String? v) => v == null || v.isEmpty;

  static DateTime? _parseTime(Object? v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;

  /// The scope a catalog request lists tests under: `g:<group>` for a group
  /// request, `s:<id>` / `c:<code>` for a school-only one, `*` (global) for an
  /// unfiltered one.
  @visibleForTesting
  static String scopeToken(
      {String? groupId, String? schoolCode, String? schoolId}) {
    if (!_blank(groupId)) return 'g:$groupId';
    if (!_blank(schoolId)) return 's:$schoolId';
    if (!_blank(schoolCode)) return 'c:$schoolCode';
    return '*';
  }

  /// Whether a cached test (listed under [scopes]; null = unknown, cached
  /// before scoping existed) belongs in the offline list of this request.
  @visibleForTesting
  static bool visibleInScope(Set<String>? scopes,
      {String? groupId, String? schoolCode, String? schoolId}) {
    if (scopes == null || scopes.isEmpty) return true;
    if (scopes.contains('*')) return true;
    if (!_blank(groupId)) return scopes.contains('g:$groupId');
    if (!_blank(schoolId) && scopes.contains('s:$schoolId')) return true;
    if (!_blank(schoolCode) && scopes.contains('c:$schoolCode')) return true;
    return false;
  }

  /// Test day clock (prune needs "misses on 2 distinct calendar days").
  @visibleForTesting
  static DateTime Function() clock = DateTime.now;

  static const _missingDaysKey = 'catalog_missing_days_v2';
  static const _globalKeysKey = 'catalog_global_test_keys';
  static const _pruneAfterDays = 2;
  static const _missingCountsCap = 500;

  static String _today() {
    final d = clock();
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';
  }

  /// Marks tests as listed by an UNFILTERED catalog request (downloaded
  /// without a school/group, or seen in such a list). Only these may ever be
  /// pruned, and only by another unfiltered request.
  Future<void> _tagGlobal(Iterable<String> keys) async {
    final add = keys.toSet();
    if (add.isEmpty) return;
    // Best effort: an untagged test is simply never pruned, and a prefs
    // failure must not fail the download that triggered this.
    try {
      final prefs = await SharedPreferences.getInstance();
      final cur =
          (prefs.getStringList(_globalKeysKey) ?? const <String>[]).toSet();
      if (cur.containsAll(add)) return;
      await prefs.setStringList(_globalKeysKey, {...cur, ...add}.toList());
    } catch (e) {
      debugPrint('TestCatalogService: could not tag global tests: $e');
    }
  }

  /// Keshdan o'chiriladigan test: (1) oldin FILTRSIZ katalog ro'yxatida
  /// ko'ringan / filtrsiz yuklangan, (2) endi filtrsiz katalogda yo'q va
  /// (3) bu MUVAFFAQIYATLI, bo'sh bo'lmagan javoblarda kamida
  /// [_pruneAfterDays] ta turli kalendar kunida takrorlangan. Maktab/guruhga
  /// bog'langan yuklashlar (filtr bilan yuklangan) hech qachon o'chirilmaydi:
  /// filtrsiz katalog ularni yashiradi, "yo'q" degani "arxivlangan" degani
  /// emas — o'quvchi yuklab olgan test Start bosilganda ishlashi shart.
  /// Saqlangan urinishi (AttemptStore) bor test hech qachon o'chirilmaydi.
  /// Qaytaradi: o'chirilganlar soni.
  Future<int> _pruneStale(Set<String> fetched, Iterable<String> cached) async {
    if (fetched.isEmpty) return 0;
    final prefs = await SharedPreferences.getInstance();
    final global = (prefs.getStringList(_globalKeysKey) ?? const <String>[]).toSet();
    final today = _today();

    final misses = <String, ({int days, String last})>{};
    try {
      final raw = prefs.getString(_missingDaysKey);
      final decoded = (raw == null || raw.isEmpty) ? null : jsonDecode(raw);
      if (decoded is Map) {
        decoded.forEach((k, v) {
          if (v is Map) {
            final n = int.tryParse(v['n']?.toString() ?? '');
            if (n != null && n > 0) {
              misses[k.toString()] = (days: n, last: v['d']?.toString() ?? '');
            }
          }
        });
      }
    } catch (e) {
      debugPrint('TestCatalogService: bad $_missingDaysKey: $e');
    }

    final next = <String, ({int days, String last})>{};
    final doomed = <String>{};
    for (final key in cached) {
      if (fetched.contains(key)) continue; // qaytdi — hisoblagich tashlanadi
      if (!global.contains(key)) continue; // filtr bilan yuklangan — daxlsiz
      final prev = misses[key];
      // The same calendar day counts once however often the list refreshes.
      final days = prev == null
          ? 1
          : (prev.last == today ? prev.days : prev.days + 1);
      if (days >= _pruneAfterDays) {
        if (await AttemptStore.load(key) != null) {
          next[key] = (days: days, last: today); // davom etayotgan urinish
        } else {
          doomed.add(key);
        }
      } else {
        next[key] = (days: days, last: today);
      }
    }
    await TestCache.deleteKeys(doomed);
    if (doomed.isNotEmpty) {
      await prefs.setStringList(
          _globalKeysKey, global.difference(doomed).toList());
    }
    final capped = Map.fromEntries(next.entries.take(_missingCountsCap));
    await prefs.setString(
        _missingDaysKey,
        jsonEncode({
          for (final e in capped.entries)
            e.key: {'n': e.value.days, 'd': e.value.last}
        }));
    return doomed.length;
  }

  /// `key@version` pairs whose cached JSON already read back fine this run.
  static final Set<String> _verified = {};

  Future<bool> _readable(String key, int version) async {
    final tag = '$key@$version';
    if (_verified.contains(tag)) return true;
    Map<String, dynamic>? data;
    try {
      data = await TestCache.get(key);
    } catch (e) {
      debugPrint('TestCatalogService: cache read $key failed: $e');
    }
    if (data == null) return false;
    _verified.add(tag);
    return true;
  }

  /// A downloaded test is only worth keeping if the engine can play it: the
  /// (optionally `test_data`-wrapped) blob has at least one non-empty variant
  /// and, when `parts` is present, it is a non-empty list. Anything else would
  /// replace a working cached copy with an empty test. (`parts` may be absent
  /// in USB-pack data, so it is not mandatory.)
  @visibleForTesting
  static bool isPlayableTestJson(Map<String, dynamic> data) {
    final blob = data['test_data'] is Map
        ? Map<String, dynamic>.from(data['test_data'] as Map)
        : data;
    final parts = blob['parts'];
    final variants = blob['variants'];
    if (parts != null && (parts is! List || parts.isEmpty)) return false;
    if (variants is! Map || variants.isEmpty) return false;
    return variants.values.any((v) => v is Map && v.isNotEmpty);
  }

  /// Testni backend'dan yuklab keshga (JSON) saqlaydi. Rasmlar bu yerda
  /// YUKLANMAYDI: ular o'quvchi tanlanganda faqat uning varianti uchun
  /// [ensureVariantImages] orqali yuklanadi.
  ///
  /// Muvaffaqiyatli kesh'ga yozilsa — true, aks holda false qaytaradi.
  ///
  /// `groupId` — tanlangan guruh ma'lum bo'lganda (yangi maktab→guruh→test
  /// oqimi, GroupSelectScreen) uzatiladi, detail fetch'ga qo'shiladi
  /// (S-001: guruh scoping xavfsizlik chegarasi). Guruhsiz maktab yoki
  /// eski (guruhdan tashqari) yuklash oqimlarida berilmaydi — orqaga moslik.
  ///
  /// `schoolCode` — tanlangan maktab kodi ma'lum bo'lganda uzatiladi;
  /// maktabga bog'langan testni yuklash uchun SHART (groupId bilan birga).
  ///
  /// `schoolId` — qarang [refresh] izohi: berilsa `schoolCode`dan ustunlik
  /// oladi, kolliziyasiz maktab aniqlash uchun.
  Future<bool> download(String testKey,
      {String? groupId, String? schoolCode, String? schoolId}) async {
    try {
      final data = await _api.fetchTest(testKey,
          groupId: groupId, schoolCode: schoolCode, schoolId: schoolId);
      if (data == null) {
        debugPrint('TestCatalogService.download($testKey): null response');
        return false;
      }

      if (!isPlayableTestJson(data)) {
        // Keep whatever is cached: a truncated / error payload must not
        // replace a working copy.
        debugPrint('TestCatalogService.download($testKey): invalid test JSON '
            '(no playable variants), cache untouched');
        return false;
      }

      final title = data['title']?.toString() ?? '';
      final grade = int.tryParse(data['grade']?.toString() ?? '') ?? 0;
      final version = parseTestVersion(data['version']);
      final jsonStr = jsonEncode(data);

      final prev = await TestCache.versionOf(testKey);
      // New version: images of the OLD spec may have changed behind the same
      // URL - drop them (unless another cached test still uses them) so the
      // prefetch below fetches fresh files.
      final stale = (prev != null && prev != version)
          ? await _urlsOnlyUsedBy(testKey)
          : const <String>[];
      await TestCache.upsert(testKey, title, grade, version, jsonStr);
      await TestCache.recordListing(testKey,
          scope: scopeToken(
              groupId: groupId, schoolCode: schoolCode, schoolId: schoolId));
      if (_blank(groupId) && _blank(schoolCode) && _blank(schoolId)) {
        await _tagGlobal([testKey]);
      }
      if (stale.isNotEmpty) await _evictImages(stale);

      // Whole-test image top-up in the background (all variants); never
      // blocks or fails this call.
      unawaited(backgroundPrefetch(testKey, data));

      return true;
    } catch (e) {
      debugPrint('TestCatalogService.download($testKey) error: $e');
      return false;
    }
  }

  /// Image URLs of the cached [testKey] that no OTHER cached test references.
  Future<List<String>> _urlsOnlyUsedBy(String testKey) async {
    try {
      final old = await TestCache.get(testKey);
      if (old == null) return const [];
      final urls = _imageUrls(old).toSet();
      if (urls.isEmpty) return const [];
      for (final row in await TestCache.all()) {
        final other = row['test_key']?.toString() ?? '';
        if (other.isEmpty || other == testKey) continue;
        final data = await TestCache.get(other);
        if (data != null) urls.removeAll(_imageUrls(data));
        if (urls.isEmpty) break;
      }
      return urls.toList();
    } catch (e) {
      debugPrint('TestCatalogService: stale image lookup failed: $e');
      return const [];
    }
  }

  Future<void> _evictImages(List<String> urls) async {
    try {
      await _store.init();
      await _loadMissing();
      var changed = false;
      for (final u in urls) {
        _store.evict(u);
        changed = _knownMissing.remove(u) || changed;
      }
      if (changed) await _saveMissing();
    } catch (e) {
      debugPrint('TestCatalogService: stale image eviction failed: $e');
    }
  }

  /// Hozir ishlayotgan yuklashlar soni — GC ular paytida ishlamaydi.
  int _activeDownloads = 0;

  Future<bool> _allPresent(List<String> urls) async {
    await _loadMissing();
    for (final u in urls) {
      if (_store.cachedFile(u) == null && !_knownMissing.contains(u)) {
        return false;
      }
    }
    return true;
  }

  /// Hech bir keshlangan testga tegishli bo'lmagan rasm fayllarini o'chiradi
  /// (best-effort, hech qachon xato tashlamaydi; yuklash ketayotganda
  /// ishlamaydi).
  Future<void> gcStore({Duration minAge = const Duration(days: 1)}) async {
    if (_activeDownloads > 0) return;
    // Pack mode: TestCache holds only the pack's tests, so `keep` would miss
    // every persistent download and the GC would delete their images.
    if (TestCache.isMemoryMode) return;
    try {
      final keep = <String>{};
      for (final row in await TestCache.all()) {
        final key = row['test_key']?.toString() ?? '';
        if (key.isEmpty) continue;
        final data = await TestCache.get(key);
        if (data == null) continue;
        keep.addAll(_imageUrls(data));
      }
      if (_activeDownloads > 0) return;
      await _store.gc(keep, minAge: minAge);
    } catch (e) {
      debugPrint('TestCatalogService.gcStore failed: $e');
    }
  }

  /// Test JSON'ning (ixtiyoriy `test_data` o'rami bilan) asosiy bloki.
  Map<String, dynamic> _blob(Map<String, dynamic> cached) =>
      cached['test_data'] is Map
          ? Map<String, dynamic>.from(cached['test_data'] as Map)
          : cached;

  /// [variant] ga tegishli rasm url'lari + umumiy (variantlardan tashqari)
  /// url'lar. Boshqa variantlarning rasmlari KIRMAYDI.
  List<String> variantImageUrls(Map<String, dynamic> cached, int variant) {
    final blob = _blob(cached);
    final variants = blob['variants'];
    final shared = <String, dynamic>{
      for (final e in cached.entries)
        if (e.key != 'test_data' && e.key != 'variants') e.key: e.value,
      for (final e in blob.entries)
        if (e.key != 'variants') e.key: e.value,
    };
    final urls = <String>{..._imageUrls(shared)};
    if (variants is Map) {
      // The variant the engine will RENDER (it falls back when the exact key
      // is missing), not the requested number.
      final key = effectiveVariantKey(variants, variant);
      final mine = key == null ? null : variants[key];
      if (mine != null) urls.addAll(_imageUrls(mine));
    }
    return urls.toList();
  }

  /// [variant] ning barcha rasmlari diskda bormi (tarmoqsiz)? 404/410 deb
  /// ma'lum rasmlar hisobga olinadi.
  Future<bool> variantImagesComplete(
          Map<String, dynamic> cached, int variant) =>
      _allPresent(variantImageUrls(cached, variant));

  /// Faqat [variant] (+ umumiy) rasmlarini doimiy do'konga yuklaydi.
  /// Do'konda bor rasmlar uchun tarmoqqa umuman chiqilmaydi. Yetishmaganlari
  /// cheklangan parallellikda yuklanadi (har biri uchun 2 ta qayta urinish).
  /// 404/410 — o'tkazib yuboriladi; boshqa xato — false (chaqiruvchi xatoni
  /// ko'rsatadi, qayta urinish mumkin). Oflayn bo'lib, avval 404 bo'lgani
  /// ma'lum rasm yetishmasa — bloklanmaydi.
  Future<bool> ensureVariantImages(Map<String, dynamic> cached, int variant,
          {void Function(int done, int total)? onProgress}) =>
      ensureUrls(variantImageUrls(cached, variant), onProgress: onProgress);

  /// ALL images of [data] (every variant) into the store - the whole-test
  /// counterpart of [ensureVariantImages] for flows that do not pick a variant
  /// up front (legacy unit1 / bob1_4 / math_gN loaders).
  Future<bool> ensureTestImages(Map<String, dynamic> data) =>
      ensureUrls(_imageUrls(data));

  /// Berilgan (fixImageUrl'dan o'tgan) url'lar ro'yxatini do'konga yuklaydi.
  Future<bool> ensureUrls(List<String> urls,
      {void Function(int done, int total)? onProgress}) async {
    if (urls.isEmpty) return true;
    _activeDownloads++;
    _foreground++;
    try {
      await _store.init();

      final missing = [
        for (final u in urls)
          if (_store.cachedFile(u) == null) u,
      ];
      if (missing.isEmpty) return true;

      final total = urls.length;
      var done = total - missing.length;
      onProgress?.call(done, total);

      // One bad URL must not abort the batch: every image gets its turn,
      // failures are collected and decide the result at the end.
      final failures = <String>[];
      var next = 0;
      Future<void> worker() async {
        while (next < missing.length) {
          final url = missing[next++];
          if (await _downloadOne(url)) {
            done++;
            onProgress?.call(done, total);
          } else {
            failures.add(url);
          }
        }
      }

      await Future.wait(List.generate(
          math.min(_imageConcurrency, missing.length), (_) => worker()));
      if (failures.isNotEmpty) {
        debugPrint('TestCatalogService.ensureUrls: ${failures.length} of '
            '${missing.length} images failed: ${failures.take(3).join(', ')}');
      }
      return failures.isEmpty;
    } finally {
      _foreground--;
      _activeDownloads--;
    }
  }

  /// Student-tap prepare in progress (priority over background prefetch).
  int _foreground = 0;

  // ---- Background prefetch of ALL images of a test --------------------

  static const _bgConcurrency = 2;

  /// One job at a time (global concurrency 2) and one job per testKey.
  Future<void> _bgTail = Future<void>.value();
  final Map<String, Future<void>> _bgJobs = {};

  /// Downloads every missing unique image of [json] (all variants) into the
  /// store in the background: gentle (2 at a time, random start jitter,
  /// 2s/8s/30s backoff per URL), single-flight per [testKey] (a call while
  /// one is queued/running returns that job), de-duplicated with the
  /// foreground prepare through the store's in-flight map, and yielding to
  /// it. Never throws; a URL that still fails is left for the next heal run
  /// or the student-tap prepare.
  Future<void> backgroundPrefetch(String testKey, Map<String, dynamic> json) {
    final running = _bgJobs[testKey];
    if (running != null) return running;
    final urls = _imageUrls(json);
    if (urls.isEmpty) return Future<void>.value();
    final job = _bgTail.then((_) => _runBackground(urls)).catchError((Object e) {
      debugPrint('Background prefetch($testKey) failed: $e');
    });
    _bgTail = job;
    _bgJobs[testKey] = job;
    job.whenComplete(() {
      if (identical(_bgJobs[testKey], job)) _bgJobs.remove(testKey);
    });
    return job;
  }

  /// The queued/running background prefetch of [testKey], or null. Roster
  /// badge: loading while non-null, awaited to know when it finished.
  Future<void>? backgroundJob(String testKey) => _bgJobs[testKey];

  /// ALL images of [cached] (every variant) are on disk or known 404/410.
  Future<bool> testImagesComplete(Map<String, dynamic> cached) =>
      _allPresent(_imageUrls(cached));

  Future<void> _runBackground(List<String> urls) async {
    await _loadMissing();
    try {
      await _store.init();
    } catch (e) {
      debugPrint('Background prefetch: store init failed: $e');
      return;
    }
    List<String> todo() => [
          for (final u in urls)
            if (_store.cachedFile(u) == null && !_knownMissing.contains(u)) u,
        ];
    if (todo().isEmpty) return;
    await Future<void>.delayed(_bgJitter());
    final queue = todo();
    var next = 0;
    _activeDownloads++;
    try {
      Future<void> worker() async {
        while (next < queue.length) {
          // The student-tap prepare has priority, and a running test must
          // never share bandwidth/CPU with a background download.
          while (_foreground > 0 || isTestRunning()) {
            await Future<void>.delayed(_bgYield);
          }
          final url = queue[next++];
          if (_store.cachedFile(url) != null) continue;
          await _backgroundOne(url);
        }
      }

      await Future.wait(List.generate(_bgConcurrency, (_) => worker()));
    } finally {
      _activeDownloads--;
    }
  }

  Future<void> _backgroundOne(String url) async {
    for (var attempt = 0; attempt <= _bgBackoff.length; attempt++) {
      try {
        await _recordFetch(url, await _store.fetch(url));
        return;
      } catch (e) {
        debugPrint('Background image failed for $url (attempt ${attempt + 1}): $e');
      }
      if (attempt < _bgBackoff.length) {
        await Future<void>.delayed(_bgBackoff[attempt]);
      }
    }
  }

  /// Updates the remembered-404 set after a successful round-trip.
  Future<void> _recordFetch(String url, StoreFetch r) async {
    if (r == StoreFetch.missing) {
      debugPrint('Image missing on server, skipped: $url');
      if (_knownMissing.add(url)) await _saveMissing();
    } else if (_knownMissing.remove(url)) {
      await _saveMissing();
    }
  }

  DateTime? _lastHeal;

  /// True while a test screen is up (read-only use of the engine's gates).
  /// Overridable for tests.
  @visibleForTesting
  static bool Function() isTestRunning = () =>
      ActiveTestGate.active.value || HeartbeatService.instance.testScreenActive;

  /// Cached tests whose images are incomplete get a background job (called
  /// on app start and after every successful catalog refresh). Never throws.
  Future<void> healIncompleteTests() async {
    // Decoding every cached test is expensive: at most once per 10 minutes,
    // and never while a test is being taken.
    final now = clock();
    final last = _lastHeal;
    if (isTestRunning() ||
        (last != null && now.difference(last) < const Duration(minutes: 10))) {
      return;
    }
    _lastHeal = now;
    try {
      for (final row in await TestCache.all()) {
        final key = row['test_key']?.toString() ?? '';
        if (key.isEmpty || _bgJobs.containsKey(key)) continue;
        final data = await TestCache.get(key);
        if (data == null) continue;
        if (await _allPresent(_imageUrls(data))) continue;
        unawaited(backgroundPrefetch(key, data));
      }
    } catch (e) {
      debugPrint('TestCatalogService.healIncompleteTests failed: $e');
    }
  }

  static const _imageConcurrency = 4;
  static const _imageRetries = 2;
  static const _missingPrefsKey = 'known_missing_image_urls';

  /// 404/410 bo'lgani ma'lum rasm url'lari (xotira + SharedPreferences).
  /// Oflayn rejimda bunday rasm testni bloklamasligi uchun kerak: do'konda
  /// hech qachon bo'lmaydi, lekin "tarmoq yo'q" bilan "serverda yo'q" farqlanadi.
  static final Set<String> _knownMissing = {};

  /// The one in-flight/finished load: every caller awaits the SAME future, so
  /// a gate check racing the first load never sees a half-empty set.
  static Future<void>? _missingLoad;

  static Future<void> _loadMissing() => _missingLoad ??= _readMissing();

  static Future<void> _readMissing() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _knownMissing.addAll(prefs.getStringList(_missingPrefsKey) ?? const []);
    } catch (e) {
      debugPrint('TestCatalogService: known-missing load failed: $e');
    }
  }

  static Future<void> _saveMissing() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = _knownMissing.toList();
      await prefs.setStringList(_missingPrefsKey,
          list.length > 500 ? list.sublist(list.length - 500) : list);
    } catch (e) {
      debugPrint('TestCatalogService: known-missing save failed: $e');
    }
  }

  @visibleForTesting
  static void resetKnownMissingForTest() {
    _knownMissing.clear();
    _missingLoad = null;
  }

  /// Renderer ishlatadigan kalit bilan bir xil (fixImageUrl) bo'lishi shart.
  List<String> _imageUrls(dynamic data) => _collectImageUrls(data)
      .map(MonitoringApi.fixImageUrl)
      .where((u) => u.isNotEmpty)
      .toSet()
      .toList();

  /// true = rasm do'konda yoki o'tkazib yuborildi; false = tarmoq xatosi.
  Future<bool> _downloadOne(String url) async {
    await _loadMissing();
    // Avval 404 bo'lgan rasm uchun qayta urinish shart emas (bitta urinish).
    final retries = _knownMissing.contains(url) ? 0 : _imageRetries;
    for (var attempt = 0; attempt <= retries; attempt++) {
      try {
        await _recordFetch(url, await _store.fetch(url));
        return true;
      } catch (e) {
        debugPrint('Image download failed for $url (attempt ${attempt + 1}): $e');
      }
      if (attempt < retries) {
        await Future<void>.delayed(_retryDelay * (attempt + 1));
      }
    }
    // Tarmoq xatosi. Avval 404 bo'lgani ma'lum rasm bo'lsa bloklamaymiz.
    return _knownMissing.contains(url);
  }

  static final RegExp _imageKey = RegExp(
      r'^(img|image|images|image_url|image_urls|imageurl|option_images|'
      r'options_images|cover|cover_image|cover_url|thumbnail|thumb|picture|'
      r'photo|diagram|illustration|src)$|(_img|_image|_images|_image_url)$',
      caseSensitive: false);
  static final RegExp _imageExt =
      RegExp(r'\.(png|jpe?g|gif|webp|svg)$', caseSensitive: false);

  /// Path of [s] without query / fragment.
  static String _pathOf(String s) {
    var end = s.length;
    for (final c in ['?', '#']) {
      final i = s.indexOf(c);
      if (i >= 0 && i < end) end = i;
    }
    return s.substring(0, end);
  }

  /// Rekursiv tarzda JSON ichidan RASM url'larini yig'adi: faqat ma'lum rasm
  /// kalitlari (`img`, `image_url`, `cover`, ...) ostidagi qiymatlar yoki
  /// kengaytmasi rasm bo'lgan (query'siz) manzillar. Savol matnidagi har bir
  /// "http..." satri (havola, manba) rasm EMAS — uni yuklash testni
  /// "tayyor emas" holatida ushlab qoladi.
  List<String> _collectImageUrls(dynamic node, {bool underImageKey = false}) {
    if (node is String) {
      final isHttp = node.startsWith('http://') || node.startsWith('https://');
      final hasExt = _imageExt.hasMatch(_pathOf(node));
      if (isHttp) return (underImageKey || hasExt) ? [node] : [];
      if (node.startsWith('/') && hasExt) {
        return [MonitoringApi.fixImageUrl(node)];
      }
      return [];
    }
    if (node is List) {
      final urls = <String>[];
      for (final item in node) {
        urls.addAll(_collectImageUrls(item, underImageKey: underImageKey));
      }
      return urls;
    }
    if (node is Map) {
      final urls = <String>[];
      for (final e in node.entries) {
        urls.addAll(_collectImageUrls(e.value,
            underImageKey: underImageKey || _imageKey.hasMatch(e.key.toString())));
      }
      return urls;
    }
    return [];
  }
}

/// Global singleton
final testCatalogService = TestCatalogService.dynamic(() => api);
