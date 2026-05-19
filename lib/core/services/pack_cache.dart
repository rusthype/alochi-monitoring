// lib/core/services/pack_cache.dart
//
// Version-based cache:
//   1. Startup'da /pack/version/ tekshiriladi (5s timeout)
//   2. Versiya o'zgarmagan → SharedPreferences dan o'qiladi
//   3. Yangi versiya → /pack/?grade=N yuklab olinadi → saqlanadi
//   4. Offline + cache bor → cache ishlatiladi
//   5. Offline + cache yo'q → local_test_data.dart fallback

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../data/local_test_data.dart';

// ── Public data structures ────────────────────────────────────────────────────

class PackVocabQ {
  final String id;
  final String cat;
  final String ans;
  final List<String> wrong;
  final String? imgUrl; // null = bundled image (fallback mode)

  const PackVocabQ({
    required this.id,
    required this.cat,
    required this.ans,
    required this.wrong,
    this.imgUrl,
  });
}

class PackEngQ {
  final String id;
  final int grade;
  final String sect;
  final String q;
  final List<String> opts;
  final String ans;

  const PackEngQ({
    required this.id,
    required this.grade,
    required this.sect,
    required this.q,
    required this.opts,
    required this.ans,
  });
}

class MonitoringPack {
  final int version;
  final String checksum;
  final List<PackVocabQ> vocab;
  final List<PackEngQ> english;
  final bool fromCache;
  final bool isFallback;

  const MonitoringPack({
    required this.version,
    required this.checksum,
    required this.vocab,
    required this.english,
    this.fromCache = false,
    this.isFallback = false,
  });

  int get vocabCount   => vocab.length;
  int get englishCount => english.length;
}

// ── Cache service ─────────────────────────────────────────────────────────────

class PackCacheService {
  static const _kVersion  = 'mon_pack_version';
  static const _kChecksum = 'mon_pack_checksum';
  static const _kVocab    = 'mon_pack_vocab';
  static const _kEnglish  = 'mon_pack_english';

  /// Ana metod: pack'ni yuklaydi (cache/API/fallback).
  /// [grade] — o'quvchi sinfi (ingliz savollarni filtrlab beradi).
  static Future<MonitoringPack> load({required int grade}) async {
    final prefs = await SharedPreferences.getInstance();

    // 1. Serverdan versiyani tekshir
    final serverVer = await api.getPackVersion();

    if (serverVer != null) {
      final srvVersion  = serverVer['version'] as int;
      final srvChecksum = serverVer['checksum'] as String? ?? '';
      final cachedVersion  = prefs.getInt(_kVersion) ?? 0;
      final cachedChecksum = prefs.getString(_kChecksum) ?? '';

      final needsUpdate = srvVersion != cachedVersion ||
                          srvChecksum != cachedChecksum;

      if (needsUpdate) {
        // 2. Yangi pack yuklab ol
        final pack = await api.getPack(grade: grade);
        if (pack != null) {
          await _savePack(prefs, srvVersion, srvChecksum, pack);
          return _fromApiPack(pack, fromCache: false);
        }
      }

      // 3. Versiya o'zgarmagan → cache dan o'qi
      final cached = _loadFromPrefs(prefs);
      if (cached != null) {
        return cached.copyWith(fromCache: true);
      }

      // 4. Server ma'lumoti bor lekin cache yo'q → yuklab ol
      final pack = await api.getPack(grade: grade);
      if (pack != null) {
        await _savePack(prefs, srvVersion, srvChecksum, pack);
        return _fromApiPack(pack, fromCache: false);
      }
    }

    // 5. Offline → cache dan o'qi
    final cached = _loadFromPrefs(prefs);
    if (cached != null) {
      return cached.copyWith(fromCache: true);
    }

    // 6. Hech nima yo'q → bundled fallback
    return _buildFallback(grade: grade);
  }

  // ── Save / Load ─────────────────────────────────────────────────────────────

  static Future<void> _savePack(
    SharedPreferences prefs,
    int version,
    String checksum,
    Map<String, dynamic> pack,
  ) async {
    await prefs.setInt(_kVersion, version);
    await prefs.setString(_kChecksum, checksum);
    await prefs.setString(_kVocab,    jsonEncode(pack['vocab']   ?? []));
    await prefs.setString(_kEnglish,  jsonEncode(pack['english'] ?? []));
  }

  static MonitoringPack? _loadFromPrefs(SharedPreferences prefs) {
    final vocabJson   = prefs.getString(_kVocab);
    final englishJson = prefs.getString(_kEnglish);
    if (vocabJson == null || englishJson == null) return null;

    try {
      final version  = prefs.getInt(_kVersion)        ?? 0;
      final checksum = prefs.getString(_kChecksum)     ?? '';
      final vocabList   = jsonDecode(vocabJson)   as List;
      final englishList = jsonDecode(englishJson) as List;

      return MonitoringPack(
        version:  version,
        checksum: checksum,
        vocab:    vocabList.map(_parseVocabQ).toList(),
        english:  englishList.map(_parseEngQ).toList(),
      );
    } catch (_) {
      return null;
    }
  }

  // ── Parsers ──────────────────────────────────────────────────────────────────

  static MonitoringPack _fromApiPack(
    Map<String, dynamic> pack, {
    required bool fromCache,
  }) {
    return MonitoringPack(
      version:   pack['version']  as int?    ?? 0,
      checksum:  pack['checksum'] as String? ?? '',
      vocab:     (pack['vocab']   as List).map(_parseVocabQ).toList(),
      english:   (pack['english'] as List).map(_parseEngQ).toList(),
      fromCache: fromCache,
    );
  }

  static PackVocabQ _parseVocabQ(dynamic j) {
    final m = j as Map<String, dynamic>;
    return PackVocabQ(
      id:     m['id']  as String? ?? '',
      cat:    m['cat'] as String? ?? 'vocab',
      ans:    m['ans'] as String? ?? '',
      wrong:  List<String>.from(m['wrong'] as List? ?? []),
      imgUrl: m['img'] as String?,
    );
  }

  static PackEngQ _parseEngQ(dynamic j) {
    final m = j as Map<String, dynamic>;
    return PackEngQ(
      id:    m['id']    as String? ?? '',
      grade: m['grade'] as int?    ?? 1,
      sect:  m['sect']  as String? ?? '',
      q:     m['q']     as String? ?? '',
      opts:  List<String>.from(m['opts'] as List? ?? []),
      ans:   m['ans']   as String? ?? '',
    );
  }

  // ── Fallback (bundled local_test_data.dart) ──────────────────────────────────

  static MonitoringPack _buildFallback({required int grade}) {
    const variantMap = {1: 'A', 2: 'B', 3: 'C', 4: 'D'};
    final variant = variantMap[grade] ?? 'A';

    final vocab = kVocabQuestions.asMap().entries.map((e) {
      return PackVocabQ(
        id:     'local_v_${e.key}',
        cat:    e.value.cat,
        ans:    e.value.ans,
        wrong:  List<String>.from(e.value.wrong),
        imgUrl: null, // base64 → local_test_data'dan olinadi
      );
    }).toList();

    final english = kEngQuestions
        .where((q) => q.variant == variant)
        .toList()
        .asMap()
        .entries
        .map((e) {
      final q = e.value;
      return PackEngQ(
        id:    'local_e_${e.key}',
        grade: grade,
        sect:  q.sect,
        q:     q.q,
        opts:  List<String>.from(q.opts),
        ans:   q.ans,
      );
    }).toList();

    return MonitoringPack(
      version:    0,
      checksum:   'fallback',
      vocab:      vocab,
      english:    english,
      isFallback: true,
    );
  }

  /// Cache'ni o'chirish (debug uchun)
  static Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kVersion);
    await prefs.remove(_kChecksum);
    await prefs.remove(_kVocab);
    await prefs.remove(_kEnglish);
  }
}

// ── Extension ─────────────────────────────────────────────────────────────────

extension _PackCopy on MonitoringPack {
  MonitoringPack copyWith({bool? fromCache, bool? isFallback}) => MonitoringPack(
        version:    version,
        checksum:   checksum,
        vocab:      vocab,
        english:    english,
        fromCache:  fromCache  ?? this.fromCache,
        isFallback: isFallback ?? this.isFallback,
      );
}
