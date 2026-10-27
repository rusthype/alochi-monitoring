// lib/features/test/engine_host_screen.dart
// Faza 4b — wires JSON-driven TestEngine into the catalog flow.
//
// Section → math/english payload mapping rules (_buildPayload):
//   TestSpec.subject == "math"     → whole-test totals go to the math field
//   TestSpec.subject == "english"  → whole-test totals go to the english field
//   TestSpec.subject == anything else (e.g. "tarix", "onatili") → both
//     {cor:0, tot:0} — that subject has no top-level bucket of its own, so it
//     doesn't silently pollute the math/english KPIs. Its real score lives
//     only in detail.sections.
//   TestSpec.subject == null (legacy tests authored before this field
//     existed) → the old per-section heuristic (isMathSection):
//       "Math" | starts-with "Matema"  → math field (correct + total)
//       Everything else                → english accumulator (yig'indi)
//     Keeps every pre-existing test's payload byte-identical.
//
// The canonical source of truth is detail.sections (full per-section scores).
// The top-level math/english/vocab fields exist only for legacy panel display.
// vocab is always {cor:0, tot:0} — engine tests don't have a separate vocab section.
//
// Duration default: 60 seconds per answerable question, clamped to [60s, 90min].

import 'dart:convert';
import 'package:flutter/material.dart';

import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/db/attempt_store.dart';
import '../../core/db/history_db.dart';
import '../../core/db/offline_queue.dart';
import '../../core/engine/test_engine.dart';
import '../../core/engine/test_models.dart';
import '../../core/engine/test_scorer.dart';
import '../../core/services/html_service.dart';
import '../../core/sync/sync_service.dart';
import '../../core/offline/lan_client_session.dart';
import '../../core/offline/offline_crypto.dart';
import '../../core/offline/offline_session.dart';
import '../diagnostic/screens/diagnostic_finished_screen.dart';
import '../offline/offline_saved_screen.dart';
import '../../shared/widgets/exit_error_scaffold.dart';
import '../../shared/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EngineHostScreen
// ─────────────────────────────────────────────────────────────────────────────

class EngineHostScreen extends StatefulWidget {
  /// Raw test data blob from TestCache.get() or a bare test_data object.
  ///
  /// Accepted shapes:
  ///   A) {test_key, title, grade, version, test_data: {...}} — from TestCache.get()
  ///   B) {test_key, title, grade, variants: {...}, ...}      — raw test blob
  final Map<String, dynamic> testData;

  final int variant;
  final String firstName;
  final String lastName;
  final String school;
  final String? group;

  /// Group id (test↔guruh bog'lanishi, 2026-07-11) — included in the
  /// result payload alongside [group] (name) so the backend can attribute
  /// the result to a specific group unambiguously.
  final String? groupId;
  final int? grade;
  final String studentId;

  /// Optional override. When null, defaults to 60 s/question (min 60s, max 90min).
  final Duration? duration;

  const EngineHostScreen({
    super.key,
    required this.testData,
    required this.variant,
    required this.firstName,
    required this.lastName,
    required this.school,
    this.group,
    this.groupId,
    this.grade,
    this.studentId = '',
    this.duration,
  });

  @override
  State<EngineHostScreen> createState() => _EngineHostScreenState();
}

class _EngineHostScreenState extends State<EngineHostScreen> {
  TestSpec? _spec;
  // Raw parse-failure state — localized lazily in build() since
  // AppLocalizations isn't available yet when _parseSpec() runs from
  // initState().
  bool _parseDataEmpty = false;
  Object? _parseException;

  // Set by _handleComplete once the test is scored. When non-null, build()
  // renders EngineResultScreen IN-PLACE instead of the running TestEngine.
  //
  // Deliberately NOT done via Navigator.pushReplacement(...) — this widget
  // (EngineHostScreen) is itself the builder for the GoRouter route
  // '/engine_host' (see lib/core/router/app_router.dart), which is reached
  // via an AWAITED `GoRouter.of(context).push('/engine_host', ...)` in
  // runner_dispatch.dart::launchRunner(). GoRouter only resolves that
  // Future when its OWN declarative Page for '/engine_host' is popped
  // through its own page-removal/onPopPage tracking. An imperative
  // Navigator.pushReplacement from inside this subtree swaps in a route
  // GoRouter never learns about (it just replaces the current entry in the
  // ambient Navigator's history) — so a later Navigator.pop() on the result
  // screen only pops that untracked route, never the '/engine_host' Page,
  // and launchRunner()'s await never resolves. That left
  // StudentEntryScreen._launching stuck true forever after "Keyingi
  // talaba" (2026-07-21 bug). Swapping the widget in-place keeps everything
  // on the single GoRouter-managed Page, so the "Keyingi talaba" button's
  // plain Navigator.of(context).pop() correctly pops '/engine_host' itself.
  ScoredResult? _completedResult;
  String? _completedToken;

  // Offline pack mode: set once the answers are in the pack's result chain.
  // build() then shows OfflineSavedScreen (no score) instead of a result.
  bool _offlineSaved = false;
  String? _completeToken;
  bool _offlineSaveFailed = false;
  VoidCallback? _offlineRetry;

  // Set by TestEngine.onExpiredAutoSubmit when a relaunch found the
  // deadline already passed and auto-submitted without the student seeing
  // it happen. EngineResultScreen shows a one-time notice for this.
  bool _expiredAutoSubmit = false;

  @override
  void initState() {
    super.initState();
    _parseSpec();
  }

  void _parseSpec() {
    try {
      // Unwrap the cache wrapper if present.
      final Map<String, dynamic> blob = (widget.testData['test_data'] is Map)
          ? Map<String, dynamic>.from(widget.testData['test_data'] as Map)
          : widget.testData;

      final spec = TestSpec.fromJson(blob);
      if (spec.variants.isEmpty) {
        _parseDataEmpty = true;
      } else {
        _spec = spec;
      }
    } catch (e) {
      _parseException = e;
    }
  }

  // ── Duration helper ─────────────────────────────────────────────────────────

  Duration _effectiveDuration(TestSpec spec) {
    if (widget.duration != null) return widget.duration!;
    if (spec.durationMinutes != null && spec.durationMinutes! > 0) {
      final mins = spec.durationMinutes!.clamp(1, 180);
      return Duration(minutes: mins);
    }
    final variantKey = widget.variant.toString();
    final sections = spec.sectionsForVariant(variantKey);
    final totalQs = sections.fold(0, (sum, s) => sum + s.questionCount);
    final secs = (totalQs * 60).clamp(60, 90 * 60);
    return Duration(seconds: secs);
  }

  // ── Section mapping ─────────────────────────────────────────────────────────

  /// True when the section name maps to the "math" bucket in the legacy payload.
  static bool isMathSection(String name) {
    final n = name.trim().toLowerCase();
    // Math World's engine section has no per-topic skill name like
    // English's Vocabulary/Grammar/... — the server sends it as the
    // generic literal "Questions" (see _qRow's identical "Questions" ->
    // "Matematika" translation). Confirmed via prod survey: every
    // subject=='combined' test's parts are exactly
    // ['Questions', 'Vocabulary', 'Spelling', 'Grammar', 'Reading',
    // 'Writing'] — no English-only test uses "Questions" as a section name.
    return n == 'math' || n.startsWith('matema') || n == 'questions';
  }

  // ── Payload builder ─────────────────────────────────────────────────────────
  //
  // Maps ScoredResult → the Map<String, dynamic> shape consumed by
  // OfflineQueue.enqueueLocal / api.submitLocalResultFull.
  // math/english top-level are for legacy panel only.
  // detail.sections is the canonical per-section breakdown.

  Map<String, dynamic> _buildPayload(ScoredResult result, int? elapsedSeconds) {
    final (math, eng) = _resolveMathEngBuckets(result, _spec?.subject);

    return <String, dynamic>{
      'name': '${widget.lastName} ${widget.firstName}',
      'grade': widget.grade ?? _spec?.grade ?? 0,
      'variant': widget.variant.toString(),
      'source': 'flutter',
      'math': {'cor': math.correct, 'tot': math.total},
      'english': {'cor': eng.correct, 'tot': eng.total},
      'vocab': {'cor': 0, 'tot': 0},
      'pct': result.totalPct.round(),
      'school_code': widget.school,
      'group_name': widget.group ?? '',
      'group_id': widget.groupId ?? '',
      'student_id': widget.studentId,
      'raw_answers': result.rawAnswers,
      if (elapsedSeconds != null && elapsedSeconds > 0)
        'duration_seconds': elapsedSeconds,
      'detail': <String, dynamic>{
        'sections': result.sectionScores
            .map((s) => <String, dynamic>{
                  'name': s.name,
                  'correct': s.correct,
                  'total': s.total,
                  'pct': s.pct,
                })
            .toList(),
        'topics': result.topicScores
            .map((t) => <String, dynamic>{
                  'name': t.topic,
                  'correct': t.correct,
                  'total': t.total,
                  'pct': t.pct,
                })
            .toList(),
        'units': result.unitScores
            .map((t) => <String, dynamic>{
                  'name': t.topic,
                  'correct': t.correct,
                  'total': t.total,
                  'pct': t.pct,
                })
            .toList(),
        if (result.shields != null) 'shields': result.shields,
        if (result.levelLabel != null) 'level': result.levelLabel,
        'test_key': result.testKey,
      },
    };
  }

  // ── onComplete ──────────────────────────────────────────────────────────────

  Future<void> _handleComplete(ScoredResult result, int? elapsedSeconds) async {
    final payload = _buildPayload(result, elapsedSeconds);
    // One token per completion: an offline retry re-appends with the SAME
    // idempotency key, so it can never create a second chain entry.
    final token = _completeToken ??= await resolveResultToken(
        result.testKey, widget.studentId);

    // Offline USB pack mode: the pack has no answer key, so the locally
    // computed score is meaningless and is never stored or shown. The answers
    // go into the pack's HMAC chain; the server scores them on import.
    // LAN client mode (phase 3) is the same story: the hub has no key either,
    // and the answers wait in the encrypted outbox until the hub acks them.
    final pack = OfflinePackSession.current;
    final lan = LanClientSession.current;
    if (pack != null || lan != null) {
      try {
        if (pack != null) {
          await pack.recordResult(payload, token: token);
        } else {
          await lan!.recordResult(payload, token: token);
        }
        await AttemptStore.clear(result.testKey);
      } catch (e) {
        debugPrint('EngineHostScreen: offline recordResult error: $e');
        if (!mounted) return;
        // Same token on retry -> the chain append is idempotent.
        setState(() {
          _offlineSaveFailed = true;
          _offlineRetry = () {
            setState(() => _offlineSaveFailed = false);
            _handleComplete(result, elapsedSeconds);
          };
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _offlineSaveFailed = false;
        _offlineSaved = true;
      });
      return;
    }

    // 1. Save to local history DB.
    try {
      final (math, eng) = _resolveMathEngBuckets(result, _spec?.subject);
      await HistoryDb.insertResult(
        firstName: widget.firstName,
        lastName: widget.lastName,
        school: widget.school,
        gradeGroup: widget.group ?? '',
        mathScore: math.correct,
        engScore: eng.correct,
        totalPct: result.totalPct,
      );
    } catch (e) {
      debugPrint('EngineHostScreen: HistoryDb error: $e');
    }

    // 2. Enqueue for offline-first sync.
    try {
      await OfflineQueue.enqueueLocal(payload, token);
    } catch (e) {
      debugPrint('EngineHostScreen: enqueueLocal error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.resultNotSavedError),
          backgroundColor: AppColors.err,
          duration: const Duration(seconds: 6),
        ));
      }
    }

    // 3. Attempt an immediate flush (fire-and-forget — don't block navigation).
    SyncService.instance.flushNow().catchError((e) {
      debugPrint('EngineHostScreen: flushNow error: $e');
      return Future<void>.value();
    });

    // 4. Submit succeeded — drop the crash-recovery attempt record so a
    // relaunch of this test starts fresh instead of "resuming" a finished one.
    try {
      await AttemptStore.clear(result.testKey);
    } catch (e) {
      debugPrint('EngineHostScreen: AttemptStore.clear error: $e');
    }

    // 5. Show result display in-place — see _completedResult doc comment
    // for why this must not be a Navigator.pushReplacement.
    if (!mounted) return;
    setState(() {
      _completedResult = result;
      _completedToken = token;
    });
  }

  // ── Build ───────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_parseDataEmpty) {
      return ExitErrorScaffold(
          message: AppLocalizations.of(context)!.testDataEmptyMsg);
    }
    if (_parseException != null) {
      return ExitErrorScaffold(
          message: AppLocalizations.of(context)!
              .testLoadErrorMsg(_parseException.toString()));
    }
    if (_spec == null) {
      return ExitErrorScaffold(
          message: AppLocalizations.of(context)!.testLoadFailed);
    }
    if (_offlineSaved || _offlineSaveFailed) {
      return OfflineSavedScreen(
        firstName: widget.firstName,
        lastName: widget.lastName,
        onNext: () => Navigator.of(context).pop(),
        onRetry: _offlineSaveFailed ? _offlineRetry : null,
      );
    }
    if (_completedResult != null) {
      return EngineResultScreen(
        firstName: widget.firstName,
        lastName: widget.lastName,
        school: widget.school,
        group: widget.group,
        grade: widget.grade ?? _spec?.grade ?? 0,
        variant: widget.variant,
        result: _completedResult!,
        clientToken: _completedToken!,
        subject: _spec?.subject,
        expiredAutoSubmit: _expiredAutoSubmit,
      );
    }

    return TestEngine(
      spec: _spec!,
      variant: widget.variant,
      firstName: widget.firstName,
      lastName: widget.lastName,
      school: widget.school,
      group: widget.group,
      studentId: widget.studentId,
      duration: _effectiveDuration(_spec!),
      onComplete: _handleComplete,
      onExpiredAutoSubmit: () => _expiredAutoSubmit = true,
    );
  }
}

/// Idempotency token for one attempt: stable across a crash-replay of the
/// SAME attempt (same `attempt_id` nonce), different for every new attempt.
///
/// A fixed-length digest (`mw-` + 40 hex = 43 chars): real combined test keys
/// are ~70 chars, and the server caps the key at 64 (online `client_token`,
/// `.alochires` meta, LAN hub).
String buildResultToken(String testKey, String studentId, String attemptId) =>
    'mw-${OfflineCrypto.sha256Hex(utf8.encode('$testKey|$studentId|$attemptId')).substring(0, 40)}';

/// Token for the attempt currently saved for [testKey]/[studentId]. Records
/// without an `attempt_id` (written by builds before it existed) or a missing
/// record fall back to a random token, i.e. the previous behaviour.
Future<String> resolveResultToken(String testKey, String studentId) async {
  final saved = await AttemptStore.load(testKey);
  final attemptId = saved?['attempt_id']?.toString() ?? '';
  if (saved != null &&
      attemptId.isNotEmpty &&
      (saved['student_id']?.toString() ?? '') == studentId) {
    return buildResultToken(testKey, studentId, attemptId);
  }
  return newIdempotencyToken();
}

// ── Internal aggregator ───────────────────────────────────────────────────────

class _Agg {
  final int correct;
  final int total;
  const _Agg(this.correct, this.total);
}

// ── Subject-aware math/english bucketing (Task 1.6 rule) ────────────────────
//
// Single source of truth for "which section(s) count toward the legacy
// top-level math/english fields", shared by _EngineHostScreenState
// (_buildPayload → backend payload, _handleComplete → local HistoryDb write)
// and _EngineResultScreenState (_buildPdfBytes → PDF report + silent
// bot-upload). All three used to re-derive this independently — two of them
// (_handleComplete, _buildPdfBytes) never picked up the subject-aware rule
// when Task 1.6 introduced it, so a Tarix/Ona tili result still showed up as
// "Ingliz tili" in the on-device Offline History screen and in the PDF
// parents/schools actually see. Top-level (not a State method) because both
// State classes need it and neither can call the other's instance methods.
//
//   subject == null      → legacy per-section-name heuristic
//                           (_EngineHostScreenState.isMathSection)
//   subject == 'math'    → every section → math bucket, english stays empty
//   subject == 'english' → every section → english bucket, math stays empty
//   subject == anything else (e.g. "tarix", "onatili", or an unrecognized
//     "combined"-style tag) → same per-section-name heuristic as the
//     null-subject path. Single-subject content tagged this way still ends
//     up entirely in one bucket (its section names never match
//     isMathSection), leaving the other at total 0 — so showMathEngRow
//     (requires BOTH totals > 0) stays false for those, unchanged from
//     before. Only genuinely mixed math+English content tagged with an
//     unrecognized subject value newly gets both buckets populated.

/// Splits [result]'s sections into the (math, english) lists per the rule
/// above. List-shaped so _buildPdfBytes can build its per-§ "Matematika"/
/// "Ingliz tili" topic tables from exactly the same decision that produces
/// the header totals below — the two can never contradict each other.
(List<SectionScore> math, List<SectionScore> eng) _resolveMathEngSections(
  ScoredResult result,
  String? subject,
) {
  if (subject == null) {
    // Legacy path — no subject field on the test JSON. Byte-identical to
    // pre-Task-1.6 behaviour.
    return _bucketBySectionName(result.sectionScores);
  }
  if (subject == 'math') return (result.sectionScores, const []);
  if (subject == 'english') return (const [], result.sectionScores);
  // Any other subject value (e.g. a "combined"-style tag we don't special-
  // case above): fall back to the same per-section-name heuristic as the
  // null-subject path. This correctly buckets genuinely mixed math+English
  // content that arrives under an unrecognized subject tag, while
  // single-subject content tagged this way (whose section names never
  // match isMathSection) still lands entirely in `eng` with `math` empty —
  // so showMathEngRow (requires BOTH totals > 0) stays false for those,
  // same as before.
  return _bucketBySectionName(result.sectionScores);
}

/// Shared per-section-name heuristic used by both the null-subject branch
/// and the unrecognized-subject fallback in [_resolveMathEngSections].
(List<SectionScore> math, List<SectionScore> eng) _bucketBySectionName(
  List<SectionScore> sections,
) {
  final math = <SectionScore>[];
  final eng = <SectionScore>[];
  for (final s in sections) {
    (_EngineHostScreenState.isMathSection(s.name) ? math : eng).add(s);
  }
  return (math, eng);
}

/// Sums a section list into a single {correct,total} aggregate.
_Agg _sumSections(List<SectionScore> sections) {
  int cor = 0, tot = 0;
  for (final s in sections) {
    cor += s.correct;
    tot += s.total;
  }
  return _Agg(cor, tot);
}

/// Scalar convenience over [_resolveMathEngSections] — what _buildPayload
/// and _handleComplete need (a single {correct,total} pair each), without
/// caring about which individual sections went into it.
(_Agg math, _Agg eng) _resolveMathEngBuckets(
    ScoredResult result, String? subject) {
  final (mathSections, engSections) = _resolveMathEngSections(result, subject);
  return (_sumSections(mathSections), _sumSections(engSections));
}

// ── Error scaffold ────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
// EngineResultScreen
//
// Post-finish screen: the student sees the neutral thank-you screen (no score).
// Keeps the silent side effects of the old result display — AI summary fetch +
// HTML report upload for the parent/teacher Telegram report, and the one-time
// "auto-submitted" notice. Independent of ResultScreen (old TestResult schema).
// ─────────────────────────────────────────────────────────────────────────────

@visibleForTesting
class EngineResultScreen extends StatefulWidget {
  final String firstName;
  final String lastName;
  final String school;
  final String? group;
  final int grade;
  final int variant;
  final ScoredResult result;
  final String clientToken;

  /// TestSpec.subject (Task 1.6), threaded through from _EngineHostScreenState
  /// so _buildPdfBytes can apply the same subject-aware math/eng bucketing
  /// rule as _buildPayload/_handleComplete instead of silently falling back
  /// to the legacy per-section-name heuristic for every test. Null for
  /// legacy tests without a subject field — see _resolveMathEngSections.
  final String? subject;

  /// True when TestEngine auto-submitted this result on relaunch because
  /// the persisted deadline had already passed — the student never saw a
  /// countdown or a confirm dialog, so this screen shows a one-time notice.
  final bool expiredAutoSubmit;

  const EngineResultScreen({
    super.key,
    required this.firstName,
    required this.lastName,
    required this.school,
    this.group,
    required this.grade,
    required this.variant,
    required this.result,
    required this.clientToken,
    this.subject,
    this.expiredAutoSubmit = false,
  });

  @override
  State<EngineResultScreen> createState() => _EngineResultScreenState();
}

class _EngineResultScreenState extends State<EngineResultScreen> {
  // AI summary (TZ §10.4) — null until loaded; stays null if offline/unavailable.
  // Never shown to the student any more; it only feeds the HTML report that
  // _autoUploadPdfForBot uploads for the parent/teacher Telegram report.
  Map<String, dynamic>? _aiSummary;

  @override
  void initState() {
    super.initState();
    _loadAiSummary().then((_) => _autoUploadPdfForBot());

    if (widget.expiredAutoSubmit) {
      // Informational only — the submit already happened, so this must
      // not block on a user response. Scheduled post-frame so the
      // Scaffold/ScaffoldMessenger this screen just mounted is ready.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(AppLocalizations.of(context)!.testAutoSubmittedNotice),
          duration: const Duration(seconds: 6),
        ));
      });
    }
  }


  /// Generates the HTML report and uploads it silently so the
  /// parent/teacher Telegram report forwards this exact file. Best-effort —
  /// any failure (offline, upload error) is swallowed.
  ///
  /// Race condition tuzatish: /result/ submit va HTML upload parallel ishlaydi.
  /// Agar natija DB ga hali yetmagan bo'lsa (404), exponential back-off bilan
  /// qayta uriniladi: 2s → 5s → 10s. Shundan keyin ham bo'lmasa — server-side
  /// fallback PDF bot ga ketadi.
  Future<void> _autoUploadPdfForBot() async {
    String? htmlStr;
    try {
      htmlStr = await _buildHtmlString();
    } catch (e) {
      debugPrint(
          'EngineResultScreen._autoUploadPdfForBot: HTML generate xato: $e');
      return;
    }

    const delays = [
      Duration(seconds: 2),
      Duration(seconds: 5),
      Duration(seconds: 10)
    ];
    for (var i = 0; i <= delays.length; i++) {
      try {
        final ok = await api.uploadResultHtml(widget.clientToken, htmlStr);
        if (ok) return; // muvaffaqiyatli yuklandi
        // ok==false → 404 (result hali serverda yo'q) — keyingi urinish
      } catch (e) {
        debugPrint(
            'EngineResultScreen._autoUploadPdfForBot attempt $i error: $e');
        return; // tarmoq xatosi — qayta urinish ma'nosiz
      }
      if (i < delays.length) {
        debugPrint(
            'EngineResultScreen._autoUploadPdfForBot: 404, ${delays[i].inSeconds}s kutilmoqda...');
        await Future<void>.delayed(delays[i]);
      }
    }
    debugPrint(
        'EngineResultScreen._autoUploadPdfForBot: barcha urinishlar tugadi, server fallback ishlaydi.');
  }

  /// Fetches the AI analysis (TZ §10.4) for the per-topic breakdown.
  /// Silent on failure — `api.fetchAiSummary` returns null offline / when the
  /// AI service is unavailable. Used only by the bot-upload HTML report.
  Future<void> _loadAiSummary() async {
    final topics = widget.result.topicScores;
    if (topics.isEmpty) return; // nothing to analyze

    try {
      final payload = topics
          .map((t) => <String, dynamic>{
                'topic': t.topic,
                'correct': t.correct,
                'total': t.total,
                'pct': t.pct.round(),
              })
          .toList();
      final data = await api.fetchAiSummary(
        grade: widget.grade,
        totalPct: widget.result.totalPct.round(),
        topics: payload,
        studentFirstName: widget.firstName,
      );
      if (!mounted) return;
      _aiSummary = data;
    } catch (e) {
      debugPrint('EngineResultScreen._loadAiSummary error: $e');
    }
  }


  /// Shared section/topic/unit computation for the HTML bot-upload report
  /// and the PDF user-facing download — keeps both in sync.
  ({
    List<MapEntry<String, ({int ok, int tot})>> mathTopics,
    List<MapEntry<String, ({int ok, int tot})>> engTopics,
    _Agg math,
    _Agg eng,
    List<MapEntry<String, ({int ok, int tot})>> topicScores,
    List<MapEntry<String, ({int ok, int tot})>> unitScores,
  }) _buildReportSections() {
    // Same subject-aware decision _buildPayload/_handleComplete use (Task
    // 1.6) — list-shaped here so the per-§ "Matematika"/"Ingliz tili" topic
    // tables below can never disagree with their own header totals (e.g. a
    // Tarix test showing "Ingliz tili: 0/0" as the header but still listing
    // its real sections underneath, contradicting itself).
    final (mathSections, engSections) =
        _resolveMathEngSections(widget.result, widget.subject);
    final mathTopics = mathSections
        .map((s) => MapEntry(s.name, (ok: s.correct, tot: s.total)))
        .toList();
    final engTopics = engSections
        .map((s) => MapEntry(s.name, (ok: s.correct, tot: s.total)))
        .toList();

    // Per-§ / per-topic breakdown + AI summary for the TZ §11 passport.
    final topicScores = widget.result.topicScores
        .map((t) => MapEntry(t.topic, (ok: t.correct, tot: t.total)))
        .toList();

    // Real per-unit breakdown ("Unit 1", "Unit 2", ...), sorted ascending by
    // unit number — mirrors the panel-frontend result-detail page's nested
    // unit rows. Empty when the test's questions carry no unit/bob tags.
    final unitScores = widget.result.unitScores
        .map((u) => MapEntry(u.topic, (ok: u.correct, tot: u.total)))
        .toList();

    return (
      mathTopics: mathTopics,
      engTopics: engTopics,
      math: _sumSections(mathSections),
      eng: _sumSections(engSections),
      topicScores: topicScores,
      unitScores: unitScores,
    );
  }

  /// Builds the result HTML string — used ONLY by the silent bot-upload (the
  /// server converts it into the parent/teacher Telegram PDF report). The
  /// user-facing "PDF hisobot" button never touches this — see _generatePdf,
  /// which builds a real PDF via PdfService so it never downloads raw HTML.
  Future<String> _buildHtmlString() async {
    final s = _buildReportSections();
    return HtmlService.generateResultHtml(
      firstName: widget.firstName,
      lastName: widget.lastName,
      group: widget.group ?? '',
      grade: widget.grade,
      variant: widget.variant,
      mathOk: s.math.correct,
      mathTotal: s.math.total,
      engOk: s.eng.correct,
      engTotal: s.eng.total,
      pct: widget.result.totalPct.round(),
      mathTopics: s.mathTopics,
      engTopics: s.engTopics,
      topicScores: s.topicScores,
      unitScores: s.unitScores,
      aiSummary: _aiSummary,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // The student never sees their score here — same thank-you screen the
    // diagnostic flow uses. "Keyingi talaba" semantics are unchanged: a plain
    // pop of the single GoRouter-managed '/engine_host' Page (see the
    // _completedResult doc comment in _EngineHostScreenState).
    return DiagnosticFinishedScreen(
      studentName: '${widget.firstName} ${widget.lastName}',
      title: l10n.testFinishedTitle,
      returnLabel: l10n.nextStudent,
      onReturn: () => Navigator.of(context).pop(),
    );
  }
}
