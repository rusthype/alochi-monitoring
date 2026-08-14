// lib/core/models/models.dart

class StudentSession {
  final String token;
  final String studentId;
  final String studentName;
  final int? variant;
  final int? grade;
  final String? groupName;
  final String schoolCode;

  const StudentSession({
    required this.token,
    required this.studentId,
    required this.studentName,
    this.variant,
    this.grade,
    this.groupName,
    this.schoolCode = '',
  });

  bool get hasActiveExam => variant != null && grade != null;

  factory StudentSession.fromJson(Map<String, dynamic> j) => StudentSession(
        token: j['token'] as String? ?? '',
        studentId: j['student_id']?.toString() ?? '',
        studentName: j['student_name'] as String? ?? '',
        variant:
            j['variant'] == null ? null : int.tryParse(j['variant'].toString()),
        grade: j['grade'] == null ? null : int.tryParse(j['grade'].toString()),
        groupName: j['group_name'] as String?,
        schoolCode: j['school_code']?.toString() ?? '',
      );
}

class TestPackage {
  final String id;
  final String title;
  final int grade;
  final int mathCount;
  final int engCount;
  final int variantCount;
  final int questionCount;

  const TestPackage({
    required this.id,
    required this.title,
    required this.grade,
    required this.mathCount,
    required this.engCount,
    required this.variantCount,
    required this.questionCount,
  });

  factory TestPackage.fromJson(Map<String, dynamic> j) => TestPackage(
        id: j['id']?.toString() ?? '',
        title: j['title'] as String? ?? '',
        grade: (j['grade'] as num?)?.toInt() ?? 9,
        mathCount: (j['math_count'] as num?)?.toInt() ?? 0,
        engCount: (j['eng_count'] as num?)?.toInt() ?? 0,
        variantCount: (j['variant_count'] as num?)?.toInt() ?? 1,
        questionCount: (j['question_count'] as num?)?.toInt() ?? 0,
      );

  int get totalCount => mathCount + engCount;
}

class Question {
  final String id;
  final String subject;
  final int position;
  final String prompt;
  final List<String> options;
  final String? image;
  // Optional per-option images (same length as options, null = text only)
  final List<String?> optionImages;

  const Question({
    required this.id,
    required this.subject,
    required this.position,
    required this.prompt,
    required this.options,
    this.image,
    this.optionImages = const [],
  });

  factory Question.fromJson(Map<String, dynamic> j) => Question(
        id: j['id']?.toString() ?? '',
        subject: j['subject'] as String? ?? '',
        position: (j['position'] as num?)?.toInt() ?? 0,
        prompt: j['prompt'] as String? ?? '',
        options: List<String>.from(j['options'] ?? []),
        image: _fixUrl(j['image'] as String?),
        optionImages: j['option_images'] != null
            ? List<String?>.from(j['option_images'])
            : const [],
      );

  bool get isMath => subject == 'math';
}

class TestResult {
  final String packageId;
  final int variant;
  final int mathScore;
  final int engScore;
  final int totalPct;
  final Map<String, String> answers;
  final String deviceId;
  final int? durationSeconds;

  const TestResult({
    required this.packageId,
    required this.variant,
    required this.mathScore,
    required this.engScore,
    required this.totalPct,
    required this.answers,
    required this.deviceId,
    this.durationSeconds,
  });

  bool get passed => totalPct >= 60;

  Map<String, dynamic> toJson({Map<String, dynamic>? detail}) => {
        'package_id': packageId,
        'variant': variant,
        'math_score': mathScore,
        'eng_score': engScore,
        'total_pct': totalPct,
        'answers': answers,
        'device_id': deviceId,
        if (detail != null) 'detail': detail,
        if (durationSeconds != null) 'duration_seconds': durationSeconds,
      };
}

class WrongAnswer {
  final int position;
  final String subject;
  final String prompt;
  final String studentAnswer;
  final String correctAnswer;
  final String studentText;
  final String correctText;
  final String? image;

  const WrongAnswer({
    required this.position,
    required this.subject,
    required this.prompt,
    required this.studentAnswer,
    required this.correctAnswer,
    required this.studentText,
    required this.correctText,
    this.image,
  });

  factory WrongAnswer.fromJson(Map<String, dynamic> j) => WrongAnswer(
        position: (j['position'] as num?)?.toInt() ?? 0,
        subject: j['subject']?.toString() ?? '',
        prompt: j['prompt']?.toString() ?? '',
        studentAnswer: j['student_answer']?.toString() ?? '',
        correctAnswer: j['correct_answer']?.toString() ?? '',
        studentText: j['student_text']?.toString() ?? '',
        correctText: j['correct_text']?.toString() ?? '',
        image: _fixUrl(j['image'] as String?),
      );
}

/// `GET /my-profile/`ning `recent_results` elementi — self-login talaba
/// dashboard'idagi "so'nggi natijalar" paneli (my_tests_screen.dart) va
/// to'liq ro'yxat ekrani (results_screen.dart) ikkalasida ham ishlatiladi,
/// shuning uchun umumiy models.dart'da.
class RecentResult {
  final String id; // MonitoringResult.id (UUID) — key for /results/<id>/breakdown/
  final String testKey;
  final String title;
  final String subject;
  final int? score; // null = missing/malformed, NEVER rendered as a fake 0%
  final DateTime? submittedAt;

  const RecentResult({
    required this.id,
    required this.testKey,
    required this.title,
    required this.subject,
    required this.score,
    this.submittedAt,
  });

  factory RecentResult.fromJson(Map<String, dynamic> j) => RecentResult(
        id: j['id']?.toString() ?? '',
        testKey: j['test_key']?.toString() ?? '',
        title: j['title']?.toString() ?? '',
        subject: j['subject']?.toString() ?? '',
        score: (j['score'] as num?)?.toInt(),
        submittedAt: j['submitted_at'] is String
            ? DateTime.tryParse(j['submitted_at'] as String)
            : null,
      );

  /// Shared `recent_results` list parser — used by both `_ProfileSummary`
  /// (my_tests_screen.dart) and `ResultsScreen._load()`, so the two never
  /// drift and both inherit the same error-handling treatment from their
  /// respective call sites' try/catch.
  static List<RecentResult> listFromJson(dynamic raw) {
    if (raw is! List || raw.isEmpty) return const [];
    return raw
        .map((e) => RecentResult.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }
}

/// `GET /results/<uuid:result_id>/breakdown/` javobi — bir natijaning
/// bob/topic/unit/part darajasidagi yig'indisi va (mavjud bo'lsa) savol-savol
/// tafsiloti. Backend har toifa uchun har xil kalit ishlatadi (bobs[].bob,
/// topics[].code/name, units[].unit, parts[].part) — shuning uchun bu yerda
/// umumiy Map ro'yxati sifatida saqlanadi (build_breakdown_from_monitoring_detail,
/// apps/monitoring/services/topic_breakdown.py bilan bir xil shakl), UI
/// tomonida to'g'ridan-to'g'ri o'sha kalitlar bilan o'qiladi.
class ResultBreakdown {
  final List<Map<String, dynamic>> bobs;
  final List<Map<String, dynamic>> topics;
  final List<Map<String, dynamic>> units;
  final List<Map<String, dynamic>> parts;
  final bool hasQuestionDetail;
  final List<QuestionBreakdownItem> questions;

  const ResultBreakdown({
    required this.bobs,
    required this.topics,
    required this.units,
    required this.parts,
    required this.hasQuestionDetail,
    required this.questions,
  });

  factory ResultBreakdown.fromJson(Map<String, dynamic> j) => ResultBreakdown(
        bobs: _mapList(j['bobs']),
        topics: _mapList(j['topics']),
        units: _mapList(j['units']),
        parts: _mapList(j['parts']),
        hasQuestionDetail: j['has_question_detail'] == true,
        questions: j['questions'] is List
            ? (j['questions'] as List)
                .whereType<Map>()
                .map((e) => QuestionBreakdownItem.fromJson(Map<String, dynamic>.from(e)))
                .toList()
            : const [],
      );
}

List<Map<String, dynamic>> _mapList(dynamic raw) {
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
}

/// One question inside [ResultBreakdown.questions] — see
/// apps/monitoring/services/question_breakdown.py's
/// `build_question_breakdown_from_monitoring_detail` docstring for the
/// exact server-side shape this mirrors field-for-field.
class QuestionBreakdownItem {
  final String sectionName;
  final String questionType;
  final String questionText;
  final List<String>? options; // choice types only
  final int? selectedIdx; // choice types only
  final int? correctIdx; // choice types only
  final dynamic selectedAnswer; // raw given value, null if unanswered
  final dynamic correctAnswer; // raw answer-key value
  final bool isCorrect;
  final bool hasAnswer;

  const QuestionBreakdownItem({
    required this.sectionName,
    required this.questionType,
    required this.questionText,
    required this.options,
    required this.selectedIdx,
    required this.correctIdx,
    required this.selectedAnswer,
    required this.correctAnswer,
    required this.isCorrect,
    required this.hasAnswer,
  });

  factory QuestionBreakdownItem.fromJson(Map<String, dynamic> j) => QuestionBreakdownItem(
        sectionName: j['section_name']?.toString() ?? '',
        questionType: j['question_type']?.toString() ?? '',
        questionText: j['question_text']?.toString() ?? '',
        options: j['options'] is List
            ? List<String>.from((j['options'] as List).map((e) => e.toString()))
            : null,
        selectedIdx: (j['selected_idx'] as num?)?.toInt(),
        correctIdx: (j['correct_idx'] as num?)?.toInt(),
        selectedAnswer: j['selected_answer'],
        correctAnswer: j['correct_answer'],
        isCorrect: j['is_correct'] == true,
        hasAnswer: j['has_answer'] == true,
      );

  /// Human-readable "what the student picked" — resolves choice-type
  /// [selectedIdx] against [options] when possible, else falls back to the
  /// raw [selectedAnswer] value.
  String selectedLabel(String noAnswerText) {
    if (!hasAnswer) return noAnswerText;
    if (options != null && selectedIdx != null && selectedIdx! >= 0 && selectedIdx! < options!.length) {
      return options![selectedIdx!];
    }
    return selectedAnswer?.toString() ?? noAnswerText;
  }

  /// Human-readable "what the correct answer was" — same resolution as
  /// [selectedLabel] but for [correctIdx]/[correctAnswer].
  String correctLabel() {
    if (options != null && correctIdx != null && correctIdx! >= 0 && correctIdx! < options!.length) {
      return options![correctIdx!];
    }
    return correctAnswer?.toString() ?? '';
  }
}

/// Image URL'ni absolute'ga o'giradi
String? _fixUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http')) return url;
  if (url.startsWith('//')) return 'https:$url';
  return 'https://api.alochi.org$url';
}
