// lib/core/models/test_catalog.dart

import 'test_version.dart';

class TestCatalogEntry {
  final String testKey;
  final String title;
  final int grade;
  final int version;
  final int imageCount;
  final String updatedAt;

  const TestCatalogEntry({
    required this.testKey,
    required this.title,
    required this.grade,
    required this.version,
    required this.imageCount,
    required this.updatedAt,
  });

  factory TestCatalogEntry.fromJson(Map<String, dynamic> j) => TestCatalogEntry(
        testKey: j['test_key'] as String? ?? '',
        title: j['title'] as String? ?? '',
        grade: (j['grade'] as num?)?.toInt() ?? 0,
        version: parseTestVersion(j['version']),
        imageCount: (j['image_count'] as num?)?.toInt() ?? 0,
        updatedAt: j['updated_at'] as String? ?? '',
      );
}
