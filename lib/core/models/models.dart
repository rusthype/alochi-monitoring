// lib/core/models/models.dart

class StudentSession {
  final String token;
  final String studentId;
  final String studentName;
  final int variant;
  final int grade;
  final String? groupName;

  const StudentSession({
    required this.token,
    required this.studentId,
    required this.studentName,
    required this.variant,
    required this.grade,
    this.groupName,
  });

  factory StudentSession.fromJson(Map<String, dynamic> j) => StudentSession(
        token:       j['token'],
        studentId:   j['student_id'],
        studentName: j['student_name'],
        variant:     j['variant'],
        grade:       j['grade'],
        groupName:   j['group_name'],
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
        id:            j['id'],
        title:         j['title'],
        grade:         j['grade'],
        mathCount:     j['math_count'],
        engCount:      j['eng_count'],
        variantCount:  j['variant_count'],
        questionCount: j['question_count'],
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
        id:       j['id'],
        subject:  j['subject'],
        position: j['position'],
        prompt:       j['prompt'],
        options:      List<String>.from(j['options'] ?? []),
        image:        _fixUrl(j['image'] as String?),
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

  const TestResult({
    required this.packageId,
    required this.variant,
    required this.mathScore,
    required this.engScore,
    required this.totalPct,
    required this.answers,
    required this.deviceId,
  });

  bool get passed => totalPct >= 60;

  Map<String, dynamic> toJson() => {
        'package_id': packageId,
        'variant':    variant,
        'math_score': mathScore,
        'eng_score':  engScore,
        'total_pct':  totalPct,
        'answers':    answers,
        'device_id':  deviceId,
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
    position:      j['position'] as int,
    subject:       j['subject'] as String,
    prompt:        j['prompt'] as String,
    studentAnswer: j['student_answer'] as String,
    correctAnswer: j['correct_answer'] as String,
    studentText:   j['student_text'] as String,
    correctText:   j['correct_text'] as String,
    image:         _fixUrl(j['image'] as String?),
  );
}

/// Image URL'ni absolute'ga o'giradi
String? _fixUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  if (url.startsWith('http')) return url;
  if (url.startsWith('//')) return 'https:$url';
  return 'https://api.alochi.org\$url';
}
