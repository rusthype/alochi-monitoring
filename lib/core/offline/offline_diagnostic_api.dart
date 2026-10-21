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

import 'package:flutter/foundation.dart';

import '../../features/diagnostic/data/diagnostic_kiosk_api.dart';
import '../db/diagnostic_answer_store.dart';
import '../api/api_client.dart' show ApiException;
import 'offline_crypto.dart';
import 'offline_errors.dart';
import 'offline_content_source.dart';
import 'offline_new_student.dart';
import '../models/add_student.dart';

class OfflineDiagnosticKioskApi extends DiagnosticKioskApi {
  final OfflineContentSource session;
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
    for (final g in session.groups) {
      if (g['id']?.toString() == id) return g;
    }
    return null;
  }

  /// Pack roster + children added on this computer (never part of the signed
  /// pack roster, see [OfflineContentSource.localStudents]).
  List<Map<String, dynamic>> get _roster =>
      [...session.students, ...session.localStudents];

  Map<String, dynamic>? _student(String id, String groupId) {
    for (final s in _roster) {
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

  /// Language of one roster student: its `language` ('uz'/'ru') when the pack
  /// carries it AND has diagnostics in that language ([packLangs]), else the
  /// pack-wide [_defaultLang] (old packs / one-language packs: unchanged).
  String _langOf(Map<String, dynamic> student, Set<String> packLangs) {
    final l = diagnosticStudentLanguage(student, '');
    return packLangs.contains(l) ? l : _defaultLang();
  }

  Set<String> get _packLangs => {for (final d in _diags) d.lang};

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
    final p = session;
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

  /// One row per class label. A class's language is the MAJORITY language of
  /// its students (tie -> 'uz'); it only drives the kiosk chrome locale and the
  /// pill badge. Each student's own test language comes from [listStudents].
  @override
  Future<(List<Map<String, dynamic>>, bool)> listClasses(
      String schoolId) async {
    final fallback = _defaultLang();
    final packLangs = _packLangs;
    final groupName = {
      for (final g in session.groups)
        g['id']?.toString() ?? '': g['name']?.toString() ?? ''
    };
    final counts = <String, Map<String, int>>{
      for (final name in groupName.values) name: <String, int>{}
    };
    for (final s in _roster) {
      final c = counts[groupName[s['group_id']?.toString() ?? '']];
      if (c == null) continue;
      final l = _langOf(s, packLangs);
      c[l] = (c[l] ?? 0) + 1;
    }
    String majority(Map<String, int> c) {
      if (c.isEmpty) return fallback;
      final top = c.values.reduce((a, b) => a > b ? a : b);
      final tied = c.keys.where((k) => c[k] == top).toList();
      return tied.contains('uz') ? 'uz' : tied.first;
    }

    final rows = <Map<String, dynamic>>[
      for (final e in counts.entries)
        {'class_label': e.key, 'language': majority(e.value)}
    ];
    return (rows, false);
  }

  @override
  Future<(List<Map<String, dynamic>>, bool)> listStudents(
      String schoolId, String classLabel) async {
    final packLangs = _packLangs;
    final groupIds = session.groups
        .where((g) => g['name']?.toString() == classLabel)
        .map((g) => g['id']?.toString() ?? '')
        .toSet();
    final rows = <Map<String, dynamic>>[];
    for (final s in _roster) {
      final gid = s['group_id']?.toString() ?? '';
      if (!groupIds.contains(gid)) continue;
      final sid = s['id']?.toString() ?? '';
      final lang = _langOf(s, packLangs);
      // Same signal the online roster carries: status + next_subject, here
      // derived from the chain (exported and unexported rows both count).
      final group = _group(gid);
      final subjects =
          _subjectsOf(_matching(group == null ? null : _gradeOf(group), lang));
      String? next;
      var done = 0;
      for (final sub in subjects) {
        if (await session
            .hasAttempt(_keyPrefix(session.packUuid, sid, gid, sub))) {
          done++;
        } else {
          next ??= sub;
        }
      }
      rows.add(<String, dynamic>{
        'attempt_id': _attemptId(sid, gid, lang),
        'student_name': s['name']?.toString() ?? '',
        'class_label': classLabel,
        'language': lang,
        'status': subjects.isEmpty || done == 0
            ? 'not_started'
            : done == subjects.length
                ? 'completed'
                : 'partial',
        'next_subject': next ?? '',
        // A child added on this computer: "Tasdiq kutilmoqda" badge.
        if (s['pending'] == true) 'pending': true,
      });
    }
    return (rows, false);
  }

  /// "Bola qo'shish" offline: the child joins the open pack's local roster
  /// (duplicate check across the whole pack, persisted per pack uuid) and is
  /// returned as an attempt row, `offline|new:<uuid>|<groupId>|<lang>`.
  @override
  Future<AddStudentResult> addStudent({
    required String schoolId,
    required String classLabel,
    required String language,
    required AddStudentDraft draft,
    bool confirmNew = false,
  }) async {
    String groupId = '';
    for (final g in session.groups) {
      if (g['name']?.toString() == classLabel) {
        groupId = g['id']?.toString() ?? '';
        break;
      }
    }
    if (groupId.isEmpty) {
      throw const ApiException(400, 'unknown class', code: 'invalid_group');
    }
    final added = await session.addLocalStudent(
        groupId: groupId,
        draft: draft,
        confirmNew: confirmNew,
        language: language);
    final lang = _langOf(
        {'language': added.language.isEmpty ? language : added.language},
        _packLangs);
    return AddStudentResult(
      id: _attemptId(added.id, groupId, lang),
      name: added.name,
      firstName: added.firstName,
      lastName: added.lastName,
      groupId: groupId,
      grade: added.grade,
      language: lang,
      classLabel: classLabel,
      status: 'not_started',
    );
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
      // The pack IS the package: report it as a ready fixed variant so the
      // roster doesn't flag every student "needs online" (CAT-only marker).
      {
        ...await startAttempt(attemptId: attemptId, subject: subject),
        'fixed_variant': true,
      };

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
    // LAN mode: the images come from the hub; pull them before the runner
    // paints the first question. (No-op for a local pack.)
    await session.prepareMedia(pick.data);
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

    final payload = attachNewStudent(<String, dynamic>{
      'name': student['name']?.toString() ?? '',
      'grade': grade ?? finished.grade,
      'variant': finished.variant.toString(),
      'source': 'flutter',
      'math': const {'cor': 0, 'tot': 0},
      'english': const {'cor': 0, 'tot': 0},
      'vocab': const {'cor': 0, 'tot': 0},
      'pct': 0,
      'school_code': session.schoolCode,
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
    }, session.localStudents);
    // meta_json.idempotency_key: unique per pack, student, group, subject AND
    // attempt ordinal, so a genuine retake is a new entry rather than being
    // swallowed. (The server keys results on the chain hash, not on this.)
    final seed =
        _keyPrefix(session.packUuid, a.studentId, a.groupId, finished.subject);
    final attemptNo = await session.nextAttemptOrdinal(seed);
    await session.recordResult(payload, token: '$seed$attemptNo');
    // The runner autosaved these into DiagnosticAnswerStore (unsynced); the
    // chain row is their only destination, so close them out or they would be
    // re-sent to the real server as attempt `offline|...` once online again.
    try {
      await DiagnosticAnswerStore.markSynced(attemptId,
          answers.map((e) => (e['question_id'] ?? '').toString()).toList());
    } catch (e) {
      debugPrint(
          'OfflineDiagnosticKioskApi: markSynced failed (non-fatal): $e');
    }

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

  /// `diag:<24 hex>:` — the attempt ordinal is appended by the caller. With the
  /// ordinal (<= 6 digits) the key stays far below the 64-char limit.
  String _keyPrefix(
          String packUuid, String studentId, String groupId, String subject) =>
      'diag:${OfflineCrypto.sha256Hex(utf8.encode('$packUuid|$studentId|$groupId|$subject')).substring(0, 24)}:';

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
