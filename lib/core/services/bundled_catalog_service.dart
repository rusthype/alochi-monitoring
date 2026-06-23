// lib/core/services/bundled_catalog_service.dart
// Bundled offline catalog: reads test JSONs from app assets (no network needed).
// img basenames ("ball.jpg") are rewritten to full asset paths before delivery.
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'test_catalog_service.dart';

const _kBundledDir = 'assets/bundled_tests/';
const _kImgDir = 'assets/bundled_tests/img/';

const _kBundledKeys = [
  'math_diag_1bob',
  'math_diag_2sinf',
  'math_diag_g1',
  'math_diag_g2',
  'eng_unit1_2',
  'eng_unit1_5',
  'math_diag_3_4',
  'eng_unit1_4',
  'eng_unit1_8',
];

class BundledCatalogService {
  /// Loads all bundled tests as CatalogEntry list (status: cached — no download needed).
  static Future<List<CatalogEntry>> loadCatalog() async {
    final entries = <CatalogEntry>[];
    for (final key in _kBundledKeys) {
      try {
        final raw = await rootBundle.loadString('$_kBundledDir$key.json');
        final data = jsonDecode(raw) as Map<String, dynamic>;
        entries.add(_toEntry(key, data));
      } catch (e) {
        debugPrint('BundledCatalogService.loadCatalog($key): $e');
      }
    }
    return entries;
  }

  /// Loads a single bundled test JSON, rewriting img basenames to full asset paths.
  static Future<Map<String, dynamic>?> loadTestData(String testKey) async {
    try {
      final raw = await rootBundle.loadString('$_kBundledDir$testKey.json');
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return _rewriteImgPaths(data) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('BundledCatalogService.loadTestData($testKey): $e');
      return null;
    }
  }

  static CatalogEntry _toEntry(String key, Map<String, dynamic> data) {
    final rawButtons = data['school_buttons'];
    final schoolButtons = <SchoolButton>[];
    if (rawButtons is List) {
      for (final btn in rawButtons) {
        if (btn is! Map) continue;
        final b = SchoolButton.fromJson(Map<String, dynamic>.from(btn));
        if (b.label.isNotEmpty && b.schoolCode.isNotEmpty) schoolButtons.add(b);
      }
    }
    final rawGrades = data['grades'];
    final grades = <int>[];
    if (rawGrades is List) {
      for (final g in rawGrades) {
        final v = int.tryParse(g?.toString() ?? '');
        if (v != null) grades.add(v);
      }
    }
    return CatalogEntry(
      testKey: key,
      title: data['title']?.toString() ?? key,
      grade: int.tryParse(data['grade']?.toString() ?? '') ?? 0,
      version: 1,
      status: CatalogStatus.cached,
      schoolButtons: schoolButtons,
      grades: grades,
    );
  }

  /// Recursively rewrites img field values from basename to full asset path.
  /// Skips values that are already network URLs (http/https).
  static dynamic _rewriteImgPaths(dynamic node) {
    if (node is Map) {
      final out = <String, dynamic>{};
      for (final e in node.entries) {
        if (e.key == 'img' && e.value is String && (e.value as String).isNotEmpty) {
          final src = e.value as String;
          out[e.key] = src.startsWith('http') ? src : '$_kImgDir$src';
        } else {
          out[e.key] = _rewriteImgPaths(e.value);
        }
      }
      return out;
    }
    if (node is List) return node.map(_rewriteImgPaths).toList();
    return node;
  }
}
