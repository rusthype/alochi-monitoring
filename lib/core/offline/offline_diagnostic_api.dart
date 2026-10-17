// lib/core/offline/offline_diagnostic_api.dart
//
// Diagnostic kiosk client served from the open `.alochipack`.
// Installed as the global `diagnosticKioskApi` by OfflinePackSession.open().
//
// The online diagnostic flow is server-driven (server-made attempts, server
// scoring). A pack instead carries plain fixed question lists under
// `diag:<subject>:g<grade>:<lang>:v<variant>` (no answer key). This adapter
// presents them to the existing runner as the "fixed variant" shape it already
// understands, derives a stateless attempt id from the roster pick, and turns
// each subject's `finishAttempt` into one entry of the pack's HMAC chain:
//
//   { ..., "test_key": "diag:math:g5:uz:v2",
//          "answers": [{"q": "<question id>", "a": "A".."D"}] }
//
// Options are delivered in AUTHORED order and never reshuffled, so the letter
// the student taps is the letter the server expects.
import 'dart:convert';

import '../../features/diagnostic/data/diagnostic_kiosk_api.dart';
import '../api/api_client.dart' show ApiException;
import 'offline_crypto.dart';
import 'offline_errors.dart';
import 'offline_session.dart';

class OfflineDiagnosticKioskApi extends DiagnosticKioskApi {
  final OfflinePackSession session;
  OfflineDiagnosticKioskApi(this.session);

  static const ApiException _unsupported = ApiException(
      0, 'offline pack mode: operation not available',
      code: kOfflineUnsupported);

  static final RegExp _diagKey =
      RegExp(r'^diag:([^:]+):g(\d+):([^:]+):v(\d+)$');
  static const List<String> _subjectOrder = ['math', 'english'];

  // ── parsed pack content ────────────────────────────────────────────────────

  Iterable<_Diag> get _diags sync* {
    for (final t in session.testsOfType('diagnostic')) {
      final key = t['key']?.toString() ?? '';
      final m = _diagKey.firstMatch(key);
      if (m == null) continue;
      yield _Diag(key, m.group(1)!, int.parse(m.group(2)!), m.group(3)!,
          int.parse(m.group(4)!), t['data']);
    }
  }

  Map<String, dynamic>? _group(String id) {
    for (final g in session.pack.groups) {
      if (g['id']?.toString() == id) return g;
    }
    return null;
  }

  Map<String, dynamic>? _student(String id, String groupId) {
    for (final s in session.pack.students) {
      if (s['id']?.toString() == id && s['group_id']?.toString() == groupId) {
        return s;
      }
    }
    return null;
  }

  /// Grade of a group: explicit `grade`, else the leading digits of its name.
  int? _gradeOf(Map<String, dynamic> group) {
    final g = group['grade'];
    if (g is num) return g.toInt();
    final m = RegExp(r'^\s*(\d+)').firstMatch(group['name']?.toString() ?? '');
    return m == null ? null : int.parse(m.group(1)!);
  }

  /// Diagnostics usable for [grade]/[lang]; falls back to every grade when the
  /// group's grade is unknown or has no diagnostics of its own.
  List<_Diag> _matching(int? grade, String lang) {
    final all = _diags.where((d) => d.lang == lang).toList();
    if (grade == null) return all;
    final exact = all.where((d) => d.grade == grade).toList();
    return exact.isNotEmpty ? exact : all;
  }

  List<String> _subjectsOf(List<_Diag> diags) {
    final subjects = diags.map((d) => d.subject).toSet().toList();
    subjects.sort((a, b) {
      final ia = _subjectOrder.indexOf(a), ib = _subjectOrder.indexOf(b);
      if (ia != ib) return (ia < 0 ? 99 : ia).compareTo(ib < 0 ? 99 : ib);
      return a.compareTo(b);
    });
    return subjects;
  }

  String _defaultLang() {
    for (final d in _diags) {
      return d.lang;
    }
    return 'uz';
  }

  // attempt_id = "offline|<studentId>|<groupId>|<lang>"
  String _attemptId(String studentId, String groupId, String lang) =>
      'offline|$studentId|$groupId|$lang';

  ({String studentId, String groupId, String lang})? _parseAttempt(String id) {
    final parts = id.split('|');
    if (parts.length != 4 || parts[0] != 'offline') return null;
    return (studentId: parts[1], groupId: parts[2], lang: parts[3]);
  }

  // ── roster ─────────────────────────────────────────────────────────────────

  @override
  Future<(List<Map<String, dynamic>>, bool)> listSchools() async {
    final p = session.pack;
    return (
      <Map<String, dynamic>>[
        {
          'school_id': p.schoolId,
          'school_name': p.schoolCode, // number only: no localized text here
          'school_number': p.schoolCode,
          'kiosk_pin': '',
        }
      ],
      false
    );
  }

  @override
  Future<(List<Map<String, dynamic>>, bool)> listClasses(
      String schoolId) async {
    final lang = _defaultLang();
    final rows = session.pack.groups
        .map((g) => <String, dynamic>{
              'class_label': g['name']?.toString() ?? '',
              'language': lang,
            })
        .toList();
    return (rows, false);
  }

  @override
  Future<(List<Map<String, dynamic>>, bool)> listStudents(
      String schoolId, String classLabel) async {
    final lang = _defaultLang();
    final groupIds = session.pack.groups
        .where((g) => g['name']?.toString() == classLabel)
        .map((g) => g['id']?.toString() ?? '')
        .toSet();
    final rows = session.pack.students
        .where((s) => groupIds.contains(s['group_id']?.toString()))
        .map((s) => <String, dynamic>{
              'attempt_id': _attemptId(s['id']?.toString() ?? '',
                  s['group_id']?.toString() ?? '', lang),
              'student_name': s['name']?.toString() ?? '',
              'class_label': classLabel,
              'language': lang,
            })
        .toList();
    return (rows, false);
  }

  // ── test content ───────────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> availableSubjects(int grade,
      {String language = 'uz'}) async {
    final subjects = _subjectsOf(_matching(grade, language));
    return {'subjects': subjects, 'config': const <String, dynamic>{}};
  }

  @override
  Future<Map<String, dynamic>> peekSubject({
    required String attemptId,
    required String subject,
  }) async =>
      // No server-side package to warm: the runner starts live (from the pack).
      const {'fixed_variant': false};

  @override
  Future<Map<String, dynamic>> startAttempt({
    required String attemptId,
    required String subject,
  }) async {
    final a = _parseAttempt(attemptId);
    final group = a == null ? null : _group(a.groupId);
    if (a == null || group == null) {
      throw const ApiException(404, 'not found in pack',
          code: kOfflineNotFound);
    }
    final candidates = _matching(_gradeOf(group), a.lang)
        .where((d) => d.subject == subject)
        .toList()
      ..sort((x, y) => x.variant.compareTo(y.variant));
    if (candidates.isEmpty) {
      throw const ApiException(404, 'not found in pack',
          code: kOfflineNotFound);
    }
    // Stable per student so a restart resumes the same variant.
    final pick = candidates[_stableHash(a.studentId) % candidates.length];
    final qs = (pick.data is Map ? (pick.data as Map)['questions'] : null);
    final questions = <Map<String, dynamic>>[
      if (qs is List)
        for (final q in qs)
          if (q is Map) _serverShape(Map<String, dynamic>.from(q)),
    ];
    return {
      'attempt_id': attemptId,
      'subject': subject,
      'is_fixed_variant': true,
      'variant_number': pick.variant,
      'test_key': pick.key,
      'total_questions': questions.length,
      'position': 1,
      'attempts_used': 0,
      'questions': questions,
    };
  }

  /// pack question -> the flat shape the runner reads (option_a..d, text,
  /// image_url, svg_visual).
  Map<String, dynamic> _serverShape(Map<String, dynamic> q) {
    final opts = q['options'] is List ? (q['options'] as List) : const [];
    String opt(int i) => i < opts.length ? opts[i].toString() : '';
    return {
      'id': q['id']?.toString() ?? '',
      'question_id': q['id']?.toString() ?? '',
      'text': q['question_text']?.toString() ?? '',
      'question_text': q['question_text']?.toString() ?? '',
      'option_a': opt(0),
      'option_b': opt(1),
      'option_c': opt(2),
      'option_d': opt(3),
      'image_url': q['image']?.toString() ?? '',
      'svg_visual': q['svg_visual']?.toString() ?? '',
      'topic': q['topic'],
      'level': q['level'],
    };
  }

  // ── answers / results ──────────────────────────────────────────────────────

  @override
  Future<Map<String, dynamic>> pingElapsed({
    required String attemptId,
    required int elapsedSeconds,
  }) async =>
      const {'ok': true};

  @override
  Future<Map<String, dynamic>> syncAnswers({
    required String attemptId,
    required List<Map<String, dynamic>> answers,
    int? generation,
  }) async =>
      const {'ok': true};

  @override
  Future<String> webTestStart({
    required String attemptId,
    required String testKey,
  }) async =>
      throw _unsupported;

  @override
  Future<Map<String, dynamic>> submitAnswer({
    required String attemptId,
    required String questionId,
    required String selected,
  }) async =>
      throw _unsupported;

  /// One finished subject -> one chain entry. There is no score offline: the
  /// response carries no `score_*`, which the runner already treats as
  /// "pending" (same as its own offline-queue path).
  @override
  Future<Map<String, dynamic>> finishAttempt({
    required String attemptId,
    required List<Map<String, dynamic>> answers,
    List<String>? flaggedQuestionIds,
    int? generation,
  }) async {
    final a = _parseAttempt(attemptId);
    final group = a == null ? null : _group(a.groupId);
    final student = a == null ? null : _student(a.studentId, a.groupId);
    if (a == null || group == null || student == null) {
      throw const ApiException(404, 'not found in pack',
          code: kOfflineNotFound);
    }
    final grade = _gradeOf(group);
    final diags = _matching(grade, a.lang);
    final subjects = _subjectsOf(diags);

    // Which subject is being finished: the one whose question ids the student
    // answered (ids are unique across diagnostic questions).
    final answered = answers
        .map((e) => (e['question_id'] ?? '').toString())
        .where((e) => e.isNotEmpty)
        .toSet();
    _Diag? finished;
    for (final d in diags) {
      final data = d.data;
      final qs = data is Map ? data['questions'] : null;
      if (qs is! List) continue;
      final ids = qs.whereType<Map>().map((q) => (q['id'] ?? '').toString());
      if (ids.any(answered.contains)) {
        finished = d;
        break;
      }
    }
    if (finished == null) {
      throw const ApiException(400, 'unknown question',
          code: 'unknown_question');
    }

    final payload = <String, dynamic>{
      'name': student['name']?.toString() ?? '',
      'grade': grade ?? finished.grade,
      'variant': finished.variant.toString(),
      'source': 'flutter',
      'math': const {'cor': 0, 'tot': 0},
      'english': const {'cor': 0, 'tot': 0},
      'vocab': const {'cor': 0, 'tot': 0},
      'pct': 0,
      'school_code': session.pack.schoolCode,
      'group_name': group['name']?.toString() ?? '',
      'group_id': a.groupId,
      'student_id': a.studentId,
      'test_key': finished.key,
      'answers': [
        for (final e in answers)
          {
            'q': (e['question_id'] ?? '').toString(),
            'a': (e['selected'] ?? '').toString(),
          }
      ],
      if (flaggedQuestionIds != null && flaggedQuestionIds.isNotEmpty)
        'flagged_question_ids': flaggedQuestionIds,
      'detail': {'test_key': finished.key, 'subject': finished.subject},
    };
    // Deterministic per (attempt, subject) so a repeated finish is a no-op.
    await session.recordResult(payload,
        token: _token('${a.studentId}:${a.groupId}:${finished.subject}'));

    final idx = subjects.indexOf(finished.subject);
    final next =
        (idx >= 0 && idx + 1 < subjects.length) ? subjects[idx + 1] : '';
    return {'ok': true, 'next_subject': next};
  }

  @override
  Future<Map<String, dynamic>> submitFinishOffline(
          Map<String, dynamic> payload, String token,
          {String subject = ''}) async =>
      // Nothing is ever queued for upload in pack mode.
      const {'synced': true};

  /// Idempotency key <= 64 chars (becomes MonitoringResult.client_token).
  /// Stable across restarts, so a repeated finish of the same subject is a
  /// duplicate rather than a second result.
  String _token(String seed) =>
      'diag:${OfflineCrypto.sha256Hex(utf8.encode(seed)).substring(0, 32)}';

  /// Process-independent hash (String.hashCode is not guaranteed stable).
  static int _stableHash(String s) {
    var h = 7;
    for (final c in s.codeUnits) {
      h = (h * 31 + c) & 0x7fffffff;
    }
    return h;
  }
}

class _Diag {
  final String key;
  final String subject;
  final int grade;
  final String lang;
  final int variant;
  final dynamic data;
  const _Diag(
      this.key, this.subject, this.grade, this.lang, this.variant, this.data);
}
