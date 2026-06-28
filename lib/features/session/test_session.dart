import '../../core/services/test_catalog_service.dart';

class TestSession {
  final String testKey;
  final String title;
  final String runnerType;
  final String schoolCode;
  final String schoolLabel;
  final int testGrade;
  final List<SchoolButton> schoolButtons;

  const TestSession({
    required this.testKey,
    required this.title,
    required this.runnerType,
    required this.schoolCode,
    required this.schoolLabel,
    required this.testGrade,
    this.schoolButtons = const [],
  });

  factory TestSession.fromEntry(
    CatalogEntry entry, {
    required String schoolCode,
    required String schoolLabel,
  }) =>
      TestSession(
        testKey: entry.testKey,
        title: entry.title,
        runnerType: entry.runnerType,
        schoolCode: schoolCode,
        schoolLabel: schoolLabel,
        testGrade: entry.grade,
        schoolButtons: entry.schoolButtons,
      );
}
