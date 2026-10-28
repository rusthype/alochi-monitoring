// lib/core/services/test_catalog_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../cache/test_image_store.dart';
import '../db/test_cache.dart';
import '../offline/lan_client_session.dart' show isOfflineModeOpen;

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
      if (cachedRows.isEmpty) {
        throw fetchError ?? Exception('catalog fetch failed');
      }
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
      final keep = entries.map((e) => e.testKey).toSet();
      await TestCache.pruneNotIn(keep);
      if (cachedVersions.keys.any((k) => !keep.contains(k))) {
        unawaited(gcStore());
      }
    } catch (e) {
      debugPrint('TestCatalogService.refresh: cache prune error: $e');
    }

    // Heal: cached tests whose images are incomplete get a background top-up.
    unawaited(healIncompleteTests());

    return entries;
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

      final title = data['title']?.toString() ?? '';
      final grade = int.tryParse(data['grade']?.toString() ?? '') ?? 0;
      final version = int.tryParse(data['version']?.toString() ?? '') ?? 0;
      final jsonStr = jsonEncode(data);

      final prev = await TestCache.versionOf(testKey);
      await TestCache.upsert(testKey, title, grade, version, jsonStr);
      // Yangi versiya: eski versiyaning rasmlari endi hech qayerda
      // ishlatilmasligi mumkin — best-effort tozalash.
      if (prev != null && prev != version) unawaited(gcStore());

      // Whole-test image top-up in the background (all variants); never
      // blocks or fails this call.
      unawaited(backgroundPrefetch(testKey, data));

      return true;
    } catch (e) {
      debugPrint('TestCatalogService.download($testKey) error: $e');
      return false;
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
      final mine = variants[variant.toString()];
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

      var failed = false;
      var next = 0;
      Future<void> worker() async {
        while (!failed && next < missing.length) {
          final url = missing[next++];
          if (!await _downloadOne(url)) {
            failed = true;
            return;
          }
          done++;
          onProgress?.call(done, total);
        }
      }

      await Future.wait(List.generate(
          math.min(_imageConcurrency, missing.length), (_) => worker()));
      return !failed;
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
          // The student-tap prepare has priority: stay out of its way.
          while (_foreground > 0) {
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

  /// Cached tests whose images are incomplete get a background job (called
  /// on app start and after every successful catalog refresh). Never throws.
  Future<void> healIncompleteTests() async {
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
  static bool _missingLoaded = false;

  static Future<void> _loadMissing() async {
    if (_missingLoaded) return;
    _missingLoaded = true;
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
    _missingLoaded = false;
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
final testCatalogService = TestCatalogService.dynamic(() => api);
