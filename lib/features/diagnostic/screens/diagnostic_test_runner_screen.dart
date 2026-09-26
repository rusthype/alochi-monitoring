// lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart
//
// CAT (adaptive) test runner — new, no existing screen pattern fits since
// the CAT engine is server-adaptive and drives one question at a time.
// Flow: availableSubjects(grade) -> startAttempt(first subject) -> loop
// submitAnswer -> render next question, or startAttempt(next_subject) on a
// subject transition, or navigate to the finished screen when done.
//
// Backend contract (alochi_backend/apps/diagnostic/views.py, CATStartView /
// CATAnswerView / _build_cat_question_response): the question dict carries
// flat option_a..option_d keys (already per-attempt shuffled) plus optional
// image_url/svg_visual, and POST cat/answer/ requires `selected` to be
// exactly "A"|"B"|"C"|"D".
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart'
    show ApiException, newIdempotencyToken;
import '../../../core/cache/image_cache_manager.dart';
import '../../../core/db/attempt_store.dart';
import '../../../core/db/diagnostic_answer_store.dart';
import '../../../core/db/diagnostic_history_db.dart';
import '../../../core/db/offline_queue.dart';
import '../../../core/services/heartbeat_service.dart';
import '../../../core/services/proctor_service.dart';
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_kiosk_api.dart';
import '../data/diagnostic_option_item.dart';
import '../utils/diagnostic_image_prefetch.dart';
import '../widgets/diagnostic_bottom_nav.dart';
import '../widgets/diagnostic_header_bar.dart';
import '../widgets/diagnostic_option_card.dart';
import '../widgets/diagnostic_options_grid.dart';
import '../widgets/diagnostic_question_card.dart';
import '../widgets/diagnostic_question_dots.dart';
import '../widgets/diagnostic_scratchpad.dart';
import '../widgets/sync_status_badge.dart';
import '../../../core/utils/student_name_formatter.dart';

export '../data/diagnostic_option_item.dart';

/// Max width of the centered content dock (question card and the floating
/// bottom-nav panel both clamp to this) for the fixed-variant redesign.
const double _kDockMaxWidth = 760;

/// Pending "subject A finished, subject B starting" state — shown as a brief
/// full-screen message instead of jumping straight to the next question.
class _SubjectTransition {
  final String from;
  final String to;
  const _SubjectTransition({required this.from, required this.to});
}

typedef DiagnosticAvailableSubjectsFn = Future<Map<String, dynamic>> Function(
  int grade, {
  String language,
});
typedef DiagnosticStartAttemptFn = Future<Map<String, dynamic>> Function({
  required String attemptId,
  required String subject,
});
typedef DiagnosticSubmitAnswerFn = Future<Map<String, dynamic>> Function({
  required String attemptId,
  required String questionId,
  required String selected,
});
typedef DiagnosticFinishAttemptFn = Future<Map<String, dynamic>> Function({
  required String attemptId,
  required List<Map<String, dynamic>> answers,
});
typedef DiagnosticPingElapsedFn = Future<Map<String, dynamic>> Function({
  required String attemptId,
  required int elapsedSeconds,
});

class DiagnosticTestRunnerScreen extends StatefulWidget {
  final String attemptId;

  /// Raw roster name (NOT patronymic-stripped) — this is what
  /// [HeartbeatService.startTest] sends as the live-monitoring identity, so
  /// it must keep whatever the backend uses to disambiguate same-name
  /// classmates. Formatted only where actually displayed on-screen (see
  /// `_buildHeader`).
  final String studentName;
  final int grade;
  final String schoolCode;
  final String language;

  /// Display-only fields threaded through purely for `DiagnosticHistoryDb`
  /// (Task 4) — never sent to any endpoint. Default to '' so every existing
  /// caller/test that doesn't pass them keeps compiling unchanged.
  final String schoolName;
  final String classLabel;

  /// Also display-only, threaded through to `DiagnosticFinishedScreen` so it
  /// can navigate straight back to this same class's roster (school id +
  /// class label) instead of the kiosk root once the student finishes.
  /// Default to '' / false so every existing caller/test keeps compiling.
  final String schoolId;
  final bool hasWebTest;
  final String webTestKey;

  /// Subject packages the student-select screen already warmed via the
  /// side-effect-free `kiosk/peek/` endpoint (see
  /// `DiagnosticStudentSelectScreen._prefetchSubjectsForStudent`) — seeded
  /// straight into `_peekedFallbackPackages` in `initState`, used only as a
  /// last-resort fallback if a real `kiosk/start/` call fails (or is
  /// skipped for the one call site that already knows it's offline). A
  /// missing/empty map just falls back to today's live-fetch behavior.
  final Map<String, Map<String, dynamic>>? prefetchedSubjects;

  /// The full subject list this attempt's grade actually has, already
  /// resolved by the student-select screen's own `availableSubjects` call
  /// (see `DiagnosticStudentSelectScreen._prefetchSubjectsForStudent`).
  /// `_bootstrap()` normally re-fetches this itself, but that live call has
  /// nothing to do with the already-cached [prefetchedSubjects] packages and
  /// its failure (e.g. offline) previously stranded a fresh attempt even
  /// when the first subject's content was sitting ready to go — see
  /// `_bootstrap`'s catch block, which falls back to this list instead of a
  /// hard error when it and a matching prefetched package are both present.
  final List<String>? prefetchedAllSubjects;

  /// Test-only overrides — default to the real [diagnosticKioskApi] methods.
  /// `diagnosticKioskApi` is a bare top-level singleton with no injectable
  /// HTTP client, so this is the smallest seam that lets widget tests fake
  /// network responses without touching that file.
  final DiagnosticAvailableSubjectsFn? availableSubjectsOverride;
  final DiagnosticStartAttemptFn? startAttemptOverride;
  final DiagnosticSubmitAnswerFn? submitAnswerOverride;
  final DiagnosticFinishAttemptFn? finishAttemptOverride;
  final DiagnosticPingElapsedFn? pingElapsedOverride;

  /// Test-only override for [OfflineQueue.enqueueLocal] — the real one opens
  /// the platform sqflite plugin, which has no channel binding under plain
  /// `flutter test` on macOS/iOS and hangs instead of throwing (see
  /// test_cache_db's sqflite_common_ffi workaround, not usable here since
  /// OfflineQueue picks its own factory). Defaults to the real call.
  final Future<void> Function(Map<String, dynamic> payload, String token)?
      enqueueLocalOverride;

  /// Test-only override for the connectivity stream `_bootstrap()` listens
  /// on to auto-retry after the very first (no-cache-yet) subject fetch
  /// fails offline. Defaults to `Connectivity().onConnectivityChanged`.
  final Stream<List<ConnectivityResult>>? connectivityStreamOverride;

  const DiagnosticTestRunnerScreen({
    super.key,
    required this.attemptId,
    required this.studentName,
    required this.grade,
    this.schoolCode = '',
    required this.language,
    this.schoolName = '',
    this.classLabel = '',
    this.schoolId = '',
    this.hasWebTest = false,
    this.webTestKey = '',
    this.prefetchedSubjects,
    this.prefetchedAllSubjects,
    this.availableSubjectsOverride,
    this.startAttemptOverride,
    this.submitAnswerOverride,
    this.finishAttemptOverride,
    this.pingElapsedOverride,
    this.enqueueLocalOverride,
    this.connectivityStreamOverride,
  });

  @override
  State<DiagnosticTestRunnerScreen> createState() =>
      _DiagnosticTestRunnerScreenState();
}

class _DiagnosticTestRunnerScreenState extends State<DiagnosticTestRunnerScreen>
    with WidgetsBindingObserver {
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  bool _subjectsEmpty = false;
  Map<String, dynamic>? _question;
  String? _selectedOption;
  int _position = 0;
  int _total = 0;
  String _currentSubject = '';
  List<String> _allSubjects = [];
  final List<String> _subjectsCompleted = [];

  /// Real, confirmed `kiosk/start/` (dry_run=False) responses fetched ahead
  /// of time in the background (every subject but the one currently being
  /// taken) so an offline mid-test subject switch never needs a live network
  /// call — see `_prefetchSubjectInBackground` and `_startSubject`. Populated
  /// EXCLUSIVELY by `_prefetchSubjectInBackground`'s success path — never
  /// seeded from `widget.prefetchedSubjects` (see [_peekedFallbackPackages]
  /// for that). Consumed (removed) once a subject is actually started; a
  /// missing entry just falls back to a live call.
  final Map<String, Map<String, dynamic>> _prefetchedSubjectPackages = {};

  /// Raw `kiosk/peek/` (dry_run=True) packages passed in from
  /// `DiagnosticStudentSelectScreen`'s bulk "download whole class" prefetch —
  /// see `widget.prefetchedSubjects`. NEVER carries `correct_display_letter`
  /// and NEVER persists `attempt.variant_number` server-side. Used ONLY as a
  /// last-resort fallback after a genuine `kiosk/start/` attempt has failed
  /// (or, for the one call site that already knows it's offline, skipped) —
  /// never trusted as a substitute for a real start on its own (see the
  /// `no_variant_number` history in `_startSubject`).
  final Map<String, Map<String, dynamic>> _peekedFallbackPackages = {};
  _SubjectTransition? _transition;

  /// Whatever network operation last failed and produced [_error] — set
  /// synchronously right before each call that can land on the error view,
  /// so Retry repeats exactly that operation (bootstrap / start-this-subject
  /// / resubmit-this-answer / finish-this-package) instead of always
  /// restarting from the first subject (see diagnostic-retry-subject-bug).
  Future<void> Function() _retryAction = () async {};

  /// Auto-retries whatever `_retryAction` currently points to once
  /// connectivity comes back — used by `_bootstrap()` (first subject fetch
  /// fails with nothing cached yet) AND `_startSubject()` (a later subject's
  /// live start-call fails offline with no prefetched package), see
  /// `_armBootstrapAutoRetry`.
  StreamSubscription<List<ConnectivityResult>>? _bootstrapRetrySub;

  /// Local UI-only bookmark state, keyed by question_id (YAGNI — no backend
  /// field/API call, see DiagnosticQuestionCard's doc comment).
  final Set<String> _flaggedQuestionIds = <String>{};

  /// Countdown seconds remaining, or null when the current attempt carries
  /// no known duration. Populated from `duration_minutes` on the
  /// start-attempt response only (see _startSubject) — per-question answer
  /// responses also carry the same value but must not reset the timer.
  int? _remainingSeconds;
  Timer? _timer;

  /// Wall-clock deadline the countdown is measured against — set once in
  /// `_startCountdownIfNeeded`. Ticking recomputes `_remainingSeconds` from
  /// `_deadline!.difference(DateTime.now())` instead of decrementing by one
  /// per fired callback: on Windows, a long-unfocused/idle/sleeping app can
  /// have its `Timer.periodic` callbacks paused for minutes or hours by the
  /// OS (a naive `remaining - 1` would then simply freeze while the student
  /// works elsewhere, effectively handing them unlimited extra real time —
  /// see the diagnostic-timer-freezes-when-unfocused investigation). Measuring
  /// against a fixed deadline makes the displayed value self-correct the
  /// moment a tick DOES fire, and `didChangeAppLifecycleState` below forces
  /// an immediate correction the moment the window regains focus, instead of
  /// waiting for the next 1-second tick.
  DateTime? _deadline;

  /// True while the admin-lock pause overlay is shown — the countdown is
  /// frozen (see [_pauseForLock]/[_resumeFromLock]), mirroring
  /// `TestEngine`'s pause/resume (kept as a plain bool + a frozen-remaining
  /// duration here since this screen measures its deadline as a `DateTime`
  /// rather than epoch-ms).
  bool _paused = false;
  Duration? _pausedRemaining;

  /// Seconds actively spent on the CURRENT subject since its countdown was
  /// last (re)seeded — a plain local counter, reset to 0 on every subject
  /// change (`_startCountdownIfNeeded`/`_restoreCountdown`). Reported to the
  /// backend's `kiosk/ping/` resilience endpoint every 30s (matching
  /// `HeartbeatService`'s own 30s ping interval) via [_pingTimer]. Not
  /// paused on app-background — the screen has no such concept today (see
  /// `didChangeAppLifecycleState`, which only corrects the countdown
  /// display), and this is a best-effort resilience signal, not the source
  /// of truth for the countdown itself.
  int _elapsedOnSubject = 0;
  Timer? _pingTimer;

  /// Auto-advance timer after a fixed-variant option select (mirrors
  /// test_screen.dart's `_autoAdv`, but 500ms per this feature's spec).
  Timer? _autoAdvance;

  /// Whether the current attempt is the fixed-variant math bank (all
  /// questions known upfront, supports prev/next/grid/finish nav) vs the
  /// CAT engine's adaptive one-question-at-a-time flow. Set from the
  /// backend's `is_fixed_variant` field on every start/answer response.
  bool _isFixedVariant = false;

  /// Full question set for a fixed-variant/full-package attempt (populated
  /// once from the start response's `questions` array) and the answers
  /// picked so far, keyed by 1-indexed position. Purely local state — once
  /// populated, prev/next/jump/select never hit the network again.
  List<Map<String, dynamic>> _questions = [];
  final Map<int, String> _answers = {};

  /// Fixed-variant-only scratchpad overlay toggle (see
  /// DiagnosticScratchpad) — never set for CAT (no trigger button rendered
  /// there, see DiagnosticQuestionCard's `onOpenScratchpad`).
  bool _scratchpadOpen = false;

  /// Local-persistence key for this attempt — reuses AttemptStore's
  /// SharedPreferences+QueueCrypto blob store (core/db/attempt_store.dart),
  /// keyed by attempt id instead of a monitoring test_key so a mid-test
  /// crash/restart on the FIXED-VARIANT path (question package answered
  /// so far + deadline) survives the same way a monitoring attempt already
  /// does — see `_tryRestore`/`_saveProgressIfFixed`. Not used for the CAT
  /// path: CAT already re-derives current progress from the server on every
  /// live start-attempt call, and has no local question package to lose.
  String get _diagKey => 'diag_${widget.attemptId}';

  /// Best-effort save of the fixed-variant attempt's local state — no-op
  /// for CAT (nothing local to lose there). Called after every subject
  /// package fetch and every answer pick.
  Future<void> _saveProgressIfFixed() async {
    if (!_isFixedVariant || _questions.isEmpty) return;
    await AttemptStore.save(_diagKey, {
      'all_subjects': _allSubjects,
      'subjects_completed': _subjectsCompleted,
      'current_subject': _currentSubject,
      'is_fixed_variant': true,
      'questions': _questions,
      // 'answers' intentionally dropped — DiagnosticAnswerStore (SQLite,
      // written per-tap in onSelect) is now the source of truth for
      // fixed-variant answers on restore (see _tryRestore); this blob's
      // debounced save is no longer the only copy, so duplicating answers
      // here would just be redundant, staler data.
      'position': _position,
      'total': _total,
      'deadline_epoch_ms': _deadline?.millisecondsSinceEpoch,
    });
  }

  /// Restores a saved fixed-variant attempt (see `_saveProgressIfFixed`)
  /// entirely from local state — no network call — mirroring
  /// `test_engine.dart`'s `_restoreAttempt`. Returns false (does nothing) if
  /// there's no saved attempt, it's a CAT attempt (no local package to
  /// restore), or its deadline has already passed — a `_bootstrap` fresh
  /// live start is the correct behavior in every one of those cases.
  Future<bool> _tryRestore() async {
    final saved = await AttemptStore.load(_diagKey);
    if (saved == null || saved['is_fixed_variant'] != true) return false;
    final questions = (saved['questions'] as List?)
        ?.whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    if (questions == null || questions.isEmpty) return false;
    final allSubjects = (saved['all_subjects'] as List?)
            ?.map((e) => e.toString())
            .where((e) => e.isNotEmpty)
            .toList() ??
        [];
    final currentSubject = (saved['current_subject'] ?? '').toString();
    if (allSubjects.isEmpty || currentSubject.isEmpty) return false;
    final deadlineMs = (saved['deadline_epoch_ms'] as num?)?.toInt();
    DateTime? deadline;
    if (deadlineMs != null) {
      deadline = DateTime.fromMillisecondsSinceEpoch(deadlineMs);
      // Expired while the app was closed — a fresh live bootstrap is
      // correct here (the server itself decides what happens next).
      if (!deadline.isAfter(DateTime.now())) return false;
    }
    // Answers now come from DiagnosticAnswerStore (SQLite), not the blob's
    // own 'answers' field (see _saveProgressIfFixed) — it's written on every
    // single tap, so it survives a crash even when this debounced blob save
    // never landed. Subject-scoped for the same reason as loadAll's own doc
    // comment: question_index is reused across subjects (Matematika 1-30,
    // then Ingliz tili 1-30 for the same attempt_id), so an unscoped read
    // would collide the two subjects' answers onto the same indexes.
    final answers = <int, String>{};
    try {
      for (final row in await DiagnosticAnswerStore.loadAll(widget.attemptId,
          subject: currentSubject)) {
        final pos = (row['question_index'] as num?)?.toInt();
        final selected = row['selected_option'] as String?;
        if (pos != null && selected != null) answers[pos] = selected;
      }
    } catch (e) {
      // A local SQLite read failure must not crash restore — degrade to
      // "no locally-saved answers found" (same tolerance as the saveAnswer/
      // clearAttempt catchError call sites above).
      debugPrint('DiagnosticAnswerStore.loadAll error: $e');
    }
    final position =
        ((saved['position'] as num?)?.toInt() ?? 1).clamp(1, questions.length);
    if (!mounted) return false;
    setState(() {
      _allSubjects = allSubjects;
      _subjectsCompleted
        ..clear()
        ..addAll(
            (saved['subjects_completed'] as List?)?.map((e) => e.toString()) ??
                const <String>[]);
      _currentSubject = currentSubject;
      _isFixedVariant = true;
      _questions = questions;
      _answers
        ..clear()
        ..addAll(answers);
      _position = position;
      _total = (saved['total'] as num?)?.toInt() ?? questions.length;
      _question = questions[position - 1];
      _selectedOption = _answers[_position];
      _loading = false;
    });
    if (deadline != null) _restoreCountdown(deadline);
    _prefetchImages(_questions);
    return true;
  }

  /// Resumes the countdown against a previously-saved (not extended)
  /// [deadline] instead of computing a fresh one from `duration_minutes` —
  /// see `_startCountdownIfNeeded`'s doc comment for why ticking is measured
  /// against a fixed wall-clock deadline rather than decremented per tick.
  void _restoreCountdown(DateTime deadline) {
    _timer?.cancel();
    _deadline = deadline;
    final remaining = deadline.difference(DateTime.now()).inSeconds;
    setState(() => _remainingSeconds = remaining > 0 ? remaining : 0);
    _timer =
        Timer.periodic(const Duration(seconds: 1), _syncRemainingFromDeadline);
    _armElapsedPingTimer();
  }

  /// Seeds the countdown from the backend's `remaining_seconds` field (2026-09
  /// resilience backend — accounts for time already spent, e.g. resuming
  /// after a power outage) when present, falling back to computing a fresh
  /// window from `duration_minutes` for older/mocked responses that don't
  /// carry it yet. `duration_minutes` alone is otherwise unused for the
  /// countdown from here on (kept only for backward compat elsewhere).
  void _startCountdownIfNeeded(Map<String, dynamic> resp) {
    final remainingFromServer = (resp['remaining_seconds'] as num?)?.toInt();
    final minutes = (resp['duration_minutes'] as num?)?.toInt();
    _timer?.cancel();
    _timer = null;
    final seconds =
        remainingFromServer ?? (minutes != null ? minutes * 60 : null);
    if (seconds == null) {
      _deadline = null;
      setState(() => _remainingSeconds = null);
      return;
    }
    _deadline = DateTime.now().add(Duration(seconds: seconds));
    setState(() => _remainingSeconds = seconds);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      _syncRemainingFromDeadline(timer);
    });
    _armElapsedPingTimer();
  }

  /// (Re)starts the per-subject elapsed-time counter and its 30s
  /// `kiosk/ping/` heartbeat — called every time a subject's countdown is
  /// (re)seeded, so Math finishing and English starting a fresh timer at 0
  /// mirrors the backend's own per-subject reset.
  void _armElapsedPingTimer() {
    _pingTimer?.cancel();
    _elapsedOnSubject = 0;
    _pingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      _elapsedOnSubject++;
      if (_elapsedOnSubject % 30 == 0) {
        unawaited(_pingElapsed());
      }
    });
  }

  /// Fire-and-forget resilience ping — never surfaced to the UI, never
  /// blocks/fails the test on error (see file header's `kiosk/ping/`
  /// contract: a nice-to-have, not a hard requirement for the test to work).
  Future<void> _pingElapsed() async {
    try {
      await _pingElapsedCall(
        attemptId: widget.attemptId,
        elapsedSeconds: _elapsedOnSubject,
      );
    } catch (e) {
      debugPrint('Diagnostic elapsed-ping failed: $e');
    }
  }

  /// Recomputes `_remainingSeconds` from `_deadline` vs the real clock (see
  /// `_deadline`'s doc comment) instead of trusting the tick count — called
  /// on every periodic tick AND once immediately on app resume.
  void _syncRemainingFromDeadline(Timer? timer) {
    final deadline = _deadline;
    if (deadline == null) {
      timer?.cancel();
      return;
    }
    final remaining = deadline.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      // _submit() may still be in flight — wait rather than race it. Do
      // NOT cancel the periodic timer in that case: the next tick (1s
      // later) re-checks, otherwise the screen would freeze at 00:00
      // forever with nothing left to trigger a re-check.
      if (_submitting) return;
      timer?.cancel();
      if (mounted) setState(() => _remainingSeconds = 0);
      // Timing out mid-subject must advance to the next incomplete subject
      // (e.g. Math -> English) exactly like a normal subject finish, not end
      // the whole attempt — see `_completeSubjectAndAdvance`. This callback
      // is sync (a `Timer.periodic` tick), so fire-and-forget it the same
      // way `_armElapsedPingTimer` does for `_pingElapsed()`.
      if (_isFixedVariant) {
        // Fixed-variant: the locally-collected answer batch was never sent
        // — finish it for real, then advance (see
        // _finishCurrentSubjectAndAdvance).
        unawaited(_finishCurrentSubjectAndAdvance());
      } else {
        // CAT: every question was already submitted in real time via
        // _submit() — nothing to flush, just advance locally (unchanged
        // behavior).
        unawaited(_completeSubjectAndAdvance(_currentSubject));
      }
      return;
    }
    if (mounted) setState(() => _remainingSeconds = remaining);
  }

  /// Freezes the countdown and shows the full-screen pause overlay. Mirrors
  /// `TestEngine._pauseForLock` — idempotent, so a duplicate `locked: true`
  /// from a replayed ping/frame response is a no-op.
  void _pauseForLock() {
    if (_paused) return;
    _timer?.cancel();
    final remaining = _deadline?.difference(DateTime.now());
    _pausedRemaining =
        remaining != null && remaining.isNegative ? Duration.zero : remaining;
    if (mounted) setState(() => _paused = true);
  }

  /// Resumes the countdown from wherever it was frozen — not from the stale
  /// pre-pause deadline, which would otherwise silently swallow however
  /// long the pause lasted.
  void _resumeFromLock() {
    if (!_paused) return;
    final remaining = _pausedRemaining;
    if (remaining != null) {
      _deadline = DateTime.now().add(remaining);
      unawaited(_saveProgressIfFixed());
    }
    _pausedRemaining = null;
    if (mounted) setState(() => _paused = false);
    _timer?.cancel();
    _timer =
        Timer.periodic(const Duration(seconds: 1), _syncRemainingFromDeadline);
    _syncRemainingFromDeadline(_timer);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // The window may have sat unfocused/minimized/asleep for a long
      // stretch, during which the OS can pause this process's Timer
      // callbacks entirely — correct the displayed countdown immediately
      // instead of waiting for the next 1-second tick to catch up.
      _syncRemainingFromDeadline(_timer);
    }
  }

  DiagnosticAvailableSubjectsFn get _availableSubjects =>
      widget.availableSubjectsOverride ?? diagnosticKioskApi.availableSubjects;
  DiagnosticStartAttemptFn get _startAttemptCall =>
      widget.startAttemptOverride ?? diagnosticKioskApi.startAttempt;
  DiagnosticSubmitAnswerFn get _submitAnswerCall =>
      widget.submitAnswerOverride ?? diagnosticKioskApi.submitAnswer;
  DiagnosticFinishAttemptFn get _finishAttemptCall =>
      widget.finishAttemptOverride ?? diagnosticKioskApi.finishAttempt;
  DiagnosticPingElapsedFn get _pingElapsedCall =>
      widget.pingElapsedOverride ?? diagnosticKioskApi.pingElapsed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final prefetched = widget.prefetchedSubjects;
    if (prefetched != null && prefetched.isNotEmpty) {
      _peekedFallbackPackages.addAll(prefetched);
    }
    _bootstrap();
    _initProctoring();
  }

  Future<void> _initProctoring() async {
    HeartbeatService.instance.onTerminated = () {
      ProctorService.instance.stop();
      HeartbeatService.instance.finishTest();
      if (mounted) {
        context.pushReplacement('/diagnostic_finished',
            extra: _finishedExtra());
      }
    };
    try {
      await HeartbeatService.instance
          .startTest(
            schoolCode: widget.schoolCode,
            name: widget.studentName,
            variant: 'CAT',
            testKey: 'diag_${widget.attemptId}',
            // DIAG- prefix matches DIAGNOSTIC_KIOSK_STUDENT_CODE_PREFIX
            // (backend apps/monitoring/selectors.py) so this session is
            // scoped to the diagnostic school's own live-monitoring tab,
            // not the global /monitoring dashboard.
            studentCode: 'DIAG-${widget.attemptId}',
          )
          .timeout(const Duration(seconds: 3));
    } catch (_) {}

    // The widget may have been disposed (dispose() already called
    // ProctorService.stop()) while the awaited call above was still
    // in flight — starting the proctor loop now would resurrect a
    // timer after teardown.
    if (!mounted) return;
    // Admin-lock/warning/extra-time callbacks live on HeartbeatService (see
    // reconcileProctorState) — the same canonical state ProctorService's
    // frame ingest and this screen's own 30s ping both feed, so pause/
    // resume/extend behave identically whichever channel reports first.
    HeartbeatService.instance
      ..onLockChanged = (locked) {
        if (!mounted) return;
        if (locked) {
          _pauseForLock();
        } else {
          _resumeFromLock();
        }
      }
      ..onExtendSeconds = (secs) {
        if (!mounted) return;
        final deadline = _deadline;
        if (deadline != null) _deadline = deadline.add(Duration(seconds: secs));
        if (_remainingSeconds != null) {
          setState(() => _remainingSeconds = _remainingSeconds! + secs);
        }
        unawaited(_saveProgressIfFixed());
      }
      ..onWarning = (msg) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(msg), backgroundColor: Colors.amber[900]),
          );
        }
      };
    ProctorService.instance.start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _pingTimer?.cancel();
    _autoAdvance?.cancel();
    _bootstrapRetrySub?.cancel();
    ProctorService.instance.stop();
    HeartbeatService.instance.finishTest();
    HeartbeatService.instance.onTerminated = null;
    HeartbeatService.instance.onLockChanged = null;
    HeartbeatService.instance.onExtendSeconds = null;
    HeartbeatService.instance.onWarning = null;
    super.dispose();
  }

  /// Listens for connectivity to come back and re-runs whatever
  /// `_retryAction` currently points to — covers both the "no internet at
  /// all yet, nothing cached" case in `_bootstrap()` and a later subject's
  /// live start-call failing offline in `_startSubject()`, where only a
  /// manual Retry button was previously available.
  void _armBootstrapAutoRetry() {
    _bootstrapRetrySub?.cancel();
    final stream = widget.connectivityStreamOverride ??
        Connectivity().onConnectivityChanged;
    _bootstrapRetrySub = stream.listen((results) {
      final online = results.isNotEmpty &&
          results.any((r) => r != ConnectivityResult.none);
      if (online) {
        _bootstrapRetrySub?.cancel();
        _bootstrapRetrySub = null;
        _retryAction();
      }
    });
  }

  /// Shared "end the test now" path — used both when the backend reports
  /// `finished: true` with no next subject, and when the countdown timer
  /// hits zero.
  void _finishTest() {
    ProctorService.instance.stop();
    HeartbeatService.instance.finishTest();
    unawaited(AttemptStore.clear(_diagKey));
    // Best-effort cleanup — a failure here must never block navigating to
    // the finished screen (see the matching saveAnswer catchError above).
    unawaited(
        DiagnosticAnswerStore.clearAttempt(widget.attemptId).catchError((e) {
      debugPrint('DiagnosticAnswerStore.clearAttempt error: $e');
    }));
    if (!mounted) return;
    context.pushReplacement('/diagnostic_finished', extra: _finishedExtra());
  }

  /// Extra payload for `/diagnostic_finished` — carries the class context
  /// through so that screen can navigate straight back to this same class's
  /// roster instead of the kiosk root. Shared by both `pushReplacement` call
  /// sites (proctoring termination + normal finish) so they can't drift.
  Map<String, dynamic> _finishedExtra() => {
        'studentName': widget.studentName,
        'subjectsCompleted': _subjectsCompleted,
        'schoolId': widget.schoolId,
        'schoolName': widget.schoolName,
        'schoolCode': widget.schoolCode,
        'classLabel': widget.classLabel,
        'language': widget.language,
        'hasWebTest': widget.hasWebTest,
        'webTestKey': widget.webTestKey,
      };

  /// Marks [subject] completed and either starts the next incomplete
  /// subject in `_allSubjects` or ends the whole attempt via `_finishTest`
  /// when none remain. Shared by every subject-transition site that has to
  /// compute the next subject itself (subject-timeout, the offline-finish
  /// self-heal, and the "allaqachon yakunlangan" self-heal in
  /// `_confirmAndFinishPackage`) — `_submit`'s and `_confirmAndFinishPackage`'s
  /// own success paths don't use this, since the backend already tells them
  /// `next_subject` directly.
  Future<void> _completeSubjectAndAdvance(String subject) async {
    _subjectsCompleted.add(subject);
    final nextSubject = _allSubjects.firstWhere(
      (s) => !_subjectsCompleted.contains(s),
      orElse: () => '',
    );
    if (nextSubject.isEmpty) {
      _finishTest();
      return;
    }
    await _startSubject(nextSubject);
  }

  Future<void> _bootstrap() async {
    _retryAction = _bootstrap;
    // Cancel any stale auto-retry listener from a previous failed attempt —
    // otherwise a successful manual retry here (e.g. a stale OS connectivity
    // reading that never fired the listener) leaves it armed, and a later
    // unrelated connectivity blip would invoke whatever `_retryAction` has
    // since become (e.g. `_submit`), causing a spurious duplicate submit.
    _bootstrapRetrySub?.cancel();
    _bootstrapRetrySub = null;
    setState(() {
      _loading = true;
      _error = null;
      _subjectsEmpty = false;
    });
    if (await _tryRestore()) return;
    try {
      final subjectsResp =
          await _availableSubjects(widget.grade, language: widget.language);
      final subjects = (subjectsResp['subjects'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          [];
      if (subjects.isEmpty) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _subjectsEmpty = true;
        });
        return;
      }
      _allSubjects = subjects;
      // NOTE: subjects beyond the first are NOT prefetched here — the
      // backend's subject-ordering guard (CATStartView.post) always 400s a
      // start-attempt call for subject N+1 until subject N is in
      // `subjects_completed`, so an eager prefetch here can never succeed
      // and only adds futile background HTTP traffic during the first
      // subject's attempt. Each next subject is instead prefetched right
      // after the current one is confirmed finished server-side (see the
      // `nextSubject` branches in `_submit` and `_confirmAndFinishPackage`),
      // which is the earliest point the backend will actually serve it.
      await _startSubject(subjects.first);
    } catch (e) {
      if (!mounted) return;
      // The live `availableSubjects` call has nothing to do with content —
      // it only learns the subject list — but a fresh (non-resumed) attempt
      // used to die here even when the student-select screen already
      // resolved that same list AND warmed the first subject's package via
      // `kiosk/peek/` (e.g. offline right after tapping a student card).
      // Fall back to that already-known list/package instead of the hard
      // error whenever both are actually available.
      final fallbackSubjects = widget.prefetchedAllSubjects;
      if (fallbackSubjects != null &&
          fallbackSubjects.isNotEmpty &&
          _peekedFallbackPackages.containsKey(fallbackSubjects.first)) {
        debugPrint('Diagnostic bootstrap: live availableSubjects failed ($e), '
            'starting from prefetched subject list/package instead');
        _allSubjects = fallbackSubjects;
        await _startSubject(fallbackSubjects.first, skipLiveCallForPeek: true);
        return;
      }
      debugPrint('Diagnostic bootstrap error: $e');
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context)!.serverErrorRetry;
      });
      _armBootstrapAutoRetry();
    }
  }

  Future<void> _startSubject(String subject,
      {bool skipLiveCallForPeek = false}) async {
    _retryAction =
        () => _startSubject(subject, skipLiveCallForPeek: skipLiveCallForPeek);
    setState(() {
      _loading = true;
      _error = null;
      _selectedOption = null;
      _transition = null;
      _currentSubject = subject;
    });
    try {
      // Always prefer a REAL, confirmed kiosk/start/ response (from
      // `_prefetchSubjectInBackground`'s success path) when one is already
      // cached — safe to use directly, no redundant live call needed.
      //
      // Otherwise, EVERY subject (first or later) always attempts the real,
      // persisting kiosk/start/ call before ever trusting a raw kiosk/peek/
      // (dry_run) fallback from `widget.prefetchedSubjects` — using peek data
      // directly would skip the real call, leaving `attempt.variant_number`
      // unset server-side forever — confirmed in production logs as the
      // dominant cause of kiosk/finish/ failing with `no_variant_number` (45
      // occurrences / 72h, 100% reproducible for any prefetched student, not
      // an intermittent/offline-only issue). This used to only be enforced
      // for the attempt's first subject (`preferCache: false` from
      // `_bootstrap`) — a later subject reached via an offline finish (no
      // background prefetch ever ran, or it ran and failed) still blindly
      // trusted whatever stale peek entry was sitting in the old shared
      // cache. Only [skipLiveCallForPeek] (the one `_bootstrap` offline-
      // fallback call site, which already knows the live call would be
      // doomed) skips straight to the peeked package instead of retrying.
      Map<String, dynamic> resp;
      final realCached = _prefetchedSubjectPackages.remove(subject);
      if (realCached != null) {
        resp = realCached;
      } else if (skipLiveCallForPeek &&
          _peekedFallbackPackages.containsKey(subject)) {
        resp = _peekedFallbackPackages.remove(subject)!;
      } else {
        try {
          resp = await _startAttemptCall(
            attemptId: widget.attemptId,
            subject: subject,
          );
        } catch (e) {
          // A 4xx business-rule rejection (e.g. "Avval math fani
          // yakunlanishi kerak") must never fall back to a stale,
          // never-persisted peek package — only a genuine network failure
          // may. Same status-code classification already used by
          // _confirmAndFinishPackage's catch block, reused here instead of
          // reinvented.
          final status = e is ApiException ? e.statusCode : 0;
          final isNetworkFailure =
              status == 0 || status >= 500 || status == 429;
          if (!isNetworkFailure) rethrow;
          final peeked = _peekedFallbackPackages.remove(subject);
          if (peeked == null) rethrow;
          resp = peeked;
        }
      }
      if (!mounted) return;
      // Re-entering an attempt the backend already finished (see
      // CATStartView's `existing.finished_at` branch) returns
      // `{finished: true, ...score summary, no question}` — previously fell
      // through to `_extractQuestion` returning null and stranding the
      // student on the generic "no data" fallback instead of the results
      // screen (diagnostic-first-card-blank-page bug).
      if (resp['finished'] == true) {
        _timer?.cancel();
        setState(() => _loading = false);
        _finishTest();
        return;
      }
      final questionsList = (resp['questions'] as List?)
          ?.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      final isFixedVariant = resp['is_fixed_variant'] == true;
      final position = (resp['position'] as num?)?.toInt() ?? 1;
      List<Map<String, dynamic>> questions = [];
      Map<String, dynamic>? question;
      if (isFixedVariant && questionsList != null && questionsList.isNotEmpty) {
        questions = questionsList;
        final idx = (position - 1).clamp(0, questions.length - 1);
        question = questions[idx];
      } else {
        question = _extractQuestion(resp);
      }
      // Await the reveal-question's image (best-effort, short timeout) so
      // the question never flashes a live-fetch spinner on first render —
      // near-instant when the package was already background-prefetched.
      await _awaitFirstImage(question);
      if (!mounted) return;
      setState(() {
        _position = position;
        _total = (resp['total_questions'] as num?)?.toInt() ?? 0;
        _isFixedVariant = isFixedVariant;
        _answers.clear();
        _questions = questions;
        _question = question;
        _loading = false;
      });
      _startCountdownIfNeeded(resp);
      final q = _question;
      HeartbeatService.instance.updateProgress(_position, _total, [],
          q != null ? _questionText(q) : null, _selectedOption);
      // Fixed-variant: whole batch known upfront — prefetch every question's
      // image now so the student never waits on a lazy load mid-test. CAT:
      // only the one question just rendered is known.
      if (_isFixedVariant) {
        _prefetchImages(_questions);
        unawaited(_saveProgressIfFixed());
      } else if (q != null) {
        _prefetchImages([q]);
      }
    } catch (e) {
      if (!mounted) return;
      // `_bootstrap()` always starts from `_allSubjects.first` — correct for
      // a brand-new attempt, but a device that closed/reopened after the
      // backend already recorded this subject as finished (e.g. the
      // subject-transition network call itself failed, see the "math
      // allaqachon yakunlangan" incident) gets this 400 back forever on
      // every reselect. Treat it the same as a normal subject-complete and
      // advance, instead of stranding the student on a "Server xatosi" that
      // a plain retry can never clear (the request never changes).
      final message = e is ApiException ? e.message : '';
      final isAlreadyCompleted =
          message.contains('$subject allaqachon yakunlangan');
      if (isAlreadyCompleted) {
        await _completeSubjectAndAdvance(subject);
        return;
      }
      debugPrint('Diagnostic start-subject "$subject" error: $e');
      setState(() {
        _loading = false;
        _error = AppLocalizations.of(context)!.serverErrorRetry;
      });
      // Bu fan uchun hech qanday prefetch kelib tushmagan (masalan
      // "Boshlash" bosilishidan oldin peek tugamagan, yoki o'tish paytidagi
      // fon-prefetch o'zi oflaynda muvaffaqiyatsiz bo'lgan) va shu jonli
      // chaqiruvning o'z zaxira-yo'li yo'q — `_confirmAndFinishPackage`dagi
      // bilan bir xil tarmoq-xatosi klassifikatsiyasi (status 0/5xx/429) va
      // `_bootstrap` allaqachon ishlatayotgan connectivity-auto-retry
      // mexanizmi orqali, faqat qo'lda "Qayta urinish" tugmasiga tayanish
      // o'rniga.
      final status = e is ApiException ? e.statusCode : 0;
      final isNetworkFailure = status == 0 || status >= 500 || status == 429;
      if (isNetworkFailure) {
        _armBootstrapAutoRetry();
      }
    }
  }

  Future<void> _submit() async {
    final q = _question;
    final selected = _selectedOption;
    if (q == null || selected == null) return;
    _retryAction = _submit;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final resp = await _submitAnswerCall(
        attemptId: widget.attemptId,
        questionId: _questionId(q),
        selected: selected,
      );
      final finished = resp['finished'] == true;
      final nextSubject = (resp['next_subject'] ?? '').toString();
      if (finished && nextSubject.isEmpty) {
        _timer?.cancel();
        _subjectsCompleted.add(_currentSubject);
        _finishTest();
        return;
      }
      if (finished && nextSubject.isNotEmpty) {
        _timer?.cancel();
        _subjectsCompleted.add(_currentSubject);
        // Earliest point the backend will actually serve the next subject's
        // content (see the ordering-guard note in `_bootstrap`) — start
        // warming it now, in parallel with the transition delay below.
        unawaited(_prefetchSubjectInBackground(nextSubject));
        if (!mounted) return;
        setState(() {
          _transition = _SubjectTransition(
            from: _currentSubject,
            to: nextSubject,
          );
        });
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        await _startSubject(nextSubject);
      } else {
        final next = _extractQuestion(resp);
        // Cache the next question's image the moment it arrives, before the
        // 1.5s reveal delay — by the time it renders it's already local.
        if (next != null) _prefetchImages([next]);
        // Keep the selected option visible (no correct/incorrect reveal)
        // for a beat before advancing, instead of a manual continue tap.
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted) return;
        setState(() {
          _question = next;
          _selectedOption = null;
          _position = (resp['position'] as num?)?.toInt() ?? _position;
          _total = (resp['total_questions'] as num?)?.toInt() ?? _total;
          _isFixedVariant = resp['is_fixed_variant'] == true;
        });
        HeartbeatService.instance.updateProgress(_position, _total, [],
            next != null ? _questionText(next) : null, _selectedOption);
      }
    } catch (e) {
      if (!mounted) return;
      debugPrint('Diagnostic submit-answer error: $e');
      // Same "stale local state" class as _confirmAndFinishPackage's
      // self-heal: the server's current_subject/question tracking has
      // drifted from what this screen still thinks it's answering (e.g.
      // "Bu savol joriy fanga tegishli emas."). A plain retry would resend
      // the exact same questionId/selected forever. Re-run _startSubject
      // for the CURRENT subject instead — it re-fetches the server's real
      // current question and fully resets local state from that response,
      // rather than trying to patch just this one submit.
      // 2026-09-18: matching a fixed allowlist of exact Uzbek error strings
      // ("Noma'lum savol" etc.) was a whack-a-mole — any NEW/unanticipated
      // stale-state message from the backend fell straight through to the
      // scary "Server xatosi" dead-end with no retry, right when a student
      // was finishing. Any 4xx here (not a network failure, not a 5xx) means
      // the SERVER responded and rejected this specific request — self-heal
      // is safe to attempt unconditionally: it just re-fetches the server's
      // authoritative current state, worst case it fails too and we fall
      // back to the exact same error as before.
      // EXCEPT 429: a rate limit is not a rejection of this request's
      // content (same distinction api_client.dart's submitLocalResultFull/
      // submitQuestionReport already make for the offline queue) — the
      // self-heal's own _startSubject call would likely just 429 again in
      // the same throttle window. Fall through to the generic retry banner
      // instead, which reuses `_retryAction = _submit` set above (retries
      // this exact answer once the window clears) rather than discarding it.
      final status = e is ApiException ? e.statusCode : 0;
      final isClientRejection = status >= 400 && status < 500 && status != 429;
      if (isClientRejection) {
        setState(() => _submitting = false);
        await _startSubject(_currentSubject);
        return;
      }
      setState(() {
        _error = AppLocalizations.of(context)!.serverErrorRetry;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  /// Local, network-free navigation for a fixed-variant/full-package
  /// attempt — [zeroBasedIndex] is clamped to the known question set.
  void _jumpTo(int zeroBasedIndex) {
    if (_questions.isEmpty) return;
    final clamped = zeroBasedIndex.clamp(0, _questions.length - 1);
    setState(() {
      _position = clamped + 1;
      _question = _questions[clamped];
      _selectedOption = _answers[_position];
    });
  }

  /// Maps [_answers] (position -> selected letter) onto [questions] by
  /// position, in the `kiosk/finish/` payload shape. Extracted so the
  /// self-heal retry in `_confirmAndFinishPackage` can rebuild the payload
  /// against a freshly-refetched package without duplicating this logic.
  List<Map<String, dynamic>> _buildFinishAnswers(
      List<Map<String, dynamic>> questions) {
    final answers = <Map<String, dynamic>>[];
    _answers.forEach((position, selected) {
      final idx = position - 1;
      if (idx < 0 || idx >= questions.length) return;
      final qid = _questionId(questions[idx]);
      if (qid.isEmpty) return;
      answers.add({'question_id': qid, 'selected': selected});
    });
    return answers;
  }

  /// Bundles this subject's correct-answer key (from the ALREADY-downloaded
  /// [questions] package's `correct_display_letter` fields — see backend
  /// `_build_cat_question_response`) alongside the offline-queued finish
  /// payload, so a finish that never reaches the server can still be
  /// self-scored later, export-time-only (DiagnosticExportService). Never
  /// null-safety-crashes on an older/stale cached package that predates
  /// this field — those entries are simply omitted from `answers`, and
  /// DiagnosticExportService treats a missing question_id as "can't score
  /// this one" rather than throwing.
  Map<String, dynamic> _buildOfflineAnswerKey(
      String subject, List<Map<String, dynamic>> questions) {
    final answers = <String, String>{};
    for (final q in questions) {
      final qid = _questionId(q);
      final letter = q['correct_display_letter'];
      if (qid.isNotEmpty && letter is String && letter.isNotEmpty) {
        answers[qid] = letter;
      }
    }
    return {'subject': subject, 'answers': answers};
  }

  /// "Quit this subject early" entry point from the bottom-nav button shown
  /// on any non-last question. Asks a distinct "are you sure" question (the
  /// student is choosing to stop, not just hitting the natural last
  /// question), then defers to [_confirmAndFinishPackage] for the actual
  /// submit — that function already re-warns about unanswered questions and
  /// already handles offline queueing / next-subject routing, so this only
  /// adds the up-front "do you really want to quit" gate.
  Future<void> _onEarlyFinishTap() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.earlyFinishConfirmTitle,
            style: const TextStyle(fontWeight: FontWeight.w800)),
        content: Text(l10n.earlyFinishConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
                minimumSize: const Size(100, 40)),
            child: Text(l10n.earlyFinishConfirmButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _confirmAndFinishPackage();
  }

  /// Finish path for a fixed-variant attempt: warns about unanswered
  /// questions (same dialog pattern as test_screen.dart's `_finish`), then
  /// submits every locally-collected answer in one `finishAttempt` call.
  Future<void> _confirmAndFinishPackage() async {
    if (_submitting) return;
    final l10n = AppLocalizations.of(context)!;
    final unanswered = _total - _answers.length;
    if (unanswered > 0) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(l10n.finishConfirmTitle,
              style: const TextStyle(fontWeight: FontWeight.w800)),
          content: Text(l10n.unansweredWarning(unanswered)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.backButton),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.brand,
                  minimumSize: const Size(100, 40)),
              child: Text(l10n.finishTest),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    await _finishCurrentSubjectAndAdvance();
  }

  /// Submits every locally-collected fixed-variant answer via `kiosk/finish/`
  /// and advances to `next_subject` (or ends the attempt). Shared by the
  /// manual "finish this subject" button (`_confirmAndFinishPackage`, after
  /// its unanswered-questions confirmation) and by `_syncRemainingFromDeadline`
  /// on subject-timer expiry (no confirmation — time is already up). Only
  /// valid for `_isFixedVariant == true`: CAT already submits each question
  /// in real time via `_submit()`, so there is no unsent local batch to
  /// flush for it.
  Future<void> _finishCurrentSubjectAndAdvance() async {
    // _submit() may still have an answer-submission in flight (the student
    // tapped in the final second) — defer rather than race it. The caller
    // (the timer tick) re-checks every second until this clears; returning
    // here must NOT be paired with cancelling the periodic timer, or the
    // screen would freeze at 00:00 forever with no further check.
    if (_submitting) return;
    final answers = _buildFinishAnswers(_questions);
    if (!mounted) return;
    _retryAction = _finishCurrentSubjectAndAdvance;
    setState(() => _submitting = true);
    Map<String, dynamic> resp;
    try {
      resp = await _finishAttemptCall(
          attemptId: widget.attemptId, answers: answers);
    } catch (e) {
      // Network failure (not a definitive rejection the server sent back) —
      // queue the finish payload for later sync via the same generic
      // local_queue OfflineQueue already uses for monitoring's offline
      // results, and let the student finish now rather than block on
      // connectivity. A definitive 4xx from the server (bad attempt_id,
      // already finished, etc.) is not a "queue and retry" case — the
      // ApiException statusCode distinguishes the two the same way
      // submitLocalResultFull/submitQuestionReport already do in
      // api_client.dart. 429 is folded in here too, same as those two
      // functions: it's a rate limit, not a rejection of this finish
      // payload, and every diagnostic kiosk endpoint (start/answer/finish)
      // shares one `diagnostic_guest` throttle scope — the self-heal path
      // below (re-fetch package, re-finish) would very likely just 429
      // again inside the same throttle window instead of succeeding.
      final status = e is ApiException ? e.statusCode : 0;
      final isNetworkFailure = status == 0 || status >= 500 || status == 429;
      if (isNetworkFailure) {
        // The finish-call itself failed transiently, but we still know the
        // full subject order locally — don't end the whole diagnostic if
        // there's another subject left to attempt (diagnostic-premature-
        // finish-on-transient-blip bug). Queue this subject's answers for
        // later sync, then try to move on to the next subject the same way
        // a successful finish-call would have; only end the test here if
        // this genuinely was the last subject.
        final enqueue =
            widget.enqueueLocalOverride ?? OfflineQueue.enqueueLocal;
        await enqueue({
          '_offlineKind': 'diagnostic_finish',
          'attempt_id': widget.attemptId,
          'answers': answers,
          '_offline_answer_key':
              _buildOfflineAnswerKey(_currentSubject, _questions),
        }, newIdempotencyToken());
        unawaited(_upsertHistoryRow(status: 'pending'));
        if (!mounted) return;
        _timer?.cancel();
        setState(() => _submitting = false);
        // No local prefetch to warm here — the finish-call's own failure
        // means we can't confirm server-side completion, so `_startSubject`
        // falls through to its normal live-call path (and surfaces its
        // existing error/retry UI if that also fails, e.g. genuine offline).
        await _completeSubjectAndAdvance(_currentSubject);
        return;
      }
      // An earlier finish-call already succeeded server-side, but its
      // response never made it back here (e.g. the connection dropped right
      // after the server wrote the result) — retrying finish again would
      // just 400 forever. Treat this exactly like a successful finish: mark
      // the subject done and let the normal flow decide the next step.
      final message = e is ApiException ? e.message : '';
      if (message.contains('allaqachon yakunlangan')) {
        _timer?.cancel();
        // No response body on this code path (the server rejected the
        // finish-call itself), so the actual score isn't available here —
        // write 'pending' rather than 'sent' so the history row doesn't
        // falsely render a blank/'-' score as if that were the real
        // result. There's no local running-score state and no GET-score
        // endpoint to backfill it from; a later sync (if this attempt ever
        // gets re-queried) can still upgrade the row via markSent.
        unawaited(_upsertHistoryRow(status: 'pending'));
        if (!mounted) return;
        setState(() => _submitting = false);
        await _completeSubjectAndAdvance(_currentSubject);
        return;
      }
      // Stale local package: server rejects a question_id/subject it no
      // longer recognizes for this attempt (e.g. a locally-cached package
      // that has drifted from the one the server actually persisted).
      // `build_full_variant_package` is idempotent per (attempt, subject) —
      // a second start-call for the SAME subject replays the persisted
      // option_map, never reshuffles — so refetching it and remapping the
      // student's already-picked answers onto it by POSITION is safe, and
      // makes the retry self-healing instead of resending the exact same
      // payload forever (a plain retry button would otherwise 400 in a
      // loop, since nothing about the stale local state ever changes).
      //
      // 2026-09-18: previously this only self-healed for a fixed allowlist
      // of exact Uzbek message substrings ("Noma'lum savol" etc.) — any
      // NEW/unanticipated 400 fell straight through to the scary "Server
      // xatosi" dead-end right when a student was finishing (the incident
      // this file's finish-offline classifier comment above also
      // describes). Any 4xx here means the server responded and rejected
      // this specific request — self-heal is safe to attempt
      // unconditionally; worst case it fails too and we fall back to the
      // exact same error as before. (429 never reaches this line — it's
      // already folded into isNetworkFailure above; `status != 429` here is
      // just a defensive belt-and-suspenders in case that changes.)
      final isClientRejection = status >= 400 && status < 500 && status != 429;
      if (!isClientRejection) {
        if (!mounted) return;
        debugPrint('Diagnostic finish-package error: $e');
        setState(() {
          _submitting = false;
          _error = AppLocalizations.of(context)!.serverErrorRetry;
        });
        return;
      }
      try {
        final freshResp = await _startAttemptCall(
          attemptId: widget.attemptId,
          subject: _currentSubject,
        );
        final freshQuestions = (freshResp['questions'] as List?)
            ?.whereType<Map>()
            .map((q) => Map<String, dynamic>.from(q))
            .toList();
        if (freshQuestions == null || freshQuestions.isEmpty) {
          rethrow;
        }
        _questions = freshQuestions;
        resp = await _finishAttemptCall(
          attemptId: widget.attemptId,
          answers: _buildFinishAnswers(freshQuestions),
        );
      } catch (_) {
        if (!mounted) return;
        debugPrint('Diagnostic finish-package error (self-heal failed): $e');
        setState(() {
          _submitting = false;
          _error = AppLocalizations.of(context)!.serverErrorRetry;
        });
        return;
      }
    }
    _timer?.cancel();
    _subjectsCompleted.add(_currentSubject);
    unawaited(_upsertHistoryRow(
      status: 'sent',
      mathScore: (resp['score_math'] as num?)?.toInt(),
      englishScore: (resp['score_english'] as num?)?.toInt(),
    ));
    final nextSubject = (resp['next_subject'] ?? '').toString();
    if (nextSubject.isNotEmpty) {
      // Same offline-resilience warm-up as the answer-submit path above
      // (see `_submit`'s identical call) — the finish-button flow reaches
      // "next_subject" just as often and deserves the same background
      // prefetch instead of only warming it from one of the two paths.
      unawaited(_prefetchSubjectInBackground(nextSubject));
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _transition = _SubjectTransition(
          from: _currentSubject,
          to: nextSubject,
        );
      });
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted) return;
      await _startSubject(nextSubject);
      return;
    }
    _finishTest();
  }

  /// Upserts this attempt's `diagnostic_history` row (Task 4) — best-effort,
  /// swallows its own errors so a local-DB hiccup never blocks the finish
  /// flow. A null score arg leaves that column untouched (see
  /// `DiagnosticHistoryDb.upsert`) — the backend only ever returns a
  /// non-null `score_math`/`score_english` for a subject once it's scored.
  Future<void> _upsertHistoryRow({
    required String status,
    int? mathScore,
    int? englishScore,
  }) async {
    try {
      await DiagnosticHistoryDb.upsert(
        attemptId: widget.attemptId,
        studentName: widget.studentName,
        classLabel: widget.classLabel,
        school: widget.schoolName,
        status: status,
        mathScore: mathScore,
        englishScore: englishScore,
      );
    } catch (e) {
      debugPrint('DiagnosticHistoryDb.upsert failed: $e');
    }
  }

  Map<String, dynamic>? _extractQuestion(Map<String, dynamic> data) {
    final nested = data['question'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    if (data['id'] != null || data['question_id'] != null) return data;
    return null;
  }

  /// Best-effort image prefetch for a batch of questions — delegates to the
  /// shared helper (`diagnostic_image_prefetch.dart`) also used by
  /// `DiagnosticStudentSelectScreen`'s student-tap prefetch, so there's
  /// exactly one URL-normalization + cache-manager call pattern.
  void _prefetchImages(List<Map<String, dynamic>> questions) =>
      prefetchDiagnosticImages(questions);

  /// Background subject-package warm-up (Bug 1) — same live call
  /// `_startSubject` would eventually make, just kicked off early and
  /// stashed in [_prefetchedSubjectPackages] instead of rendered. Failures
  /// (most commonly: offline from the start) are swallowed — the subject
  /// simply stays unprefetched and `_startSubject` falls back to a live
  /// call (with today's existing error/retry UI) when the student reaches it.
  Future<void> _prefetchSubjectInBackground(String subject) async {
    try {
      final resp = await _startAttemptCall(
        attemptId: widget.attemptId,
        subject: subject,
      );
      if (resp['finished'] == true) return;
      _prefetchedSubjectPackages[subject] = resp;
      final questionsList = (resp['questions'] as List?)
          ?.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (resp['is_fixed_variant'] == true &&
          questionsList != null &&
          questionsList.isNotEmpty) {
        _prefetchImages(questionsList);
      } else {
        final q = _extractQuestion(resp);
        if (q != null) _prefetchImages([q]);
      }
    } catch (e) {
      debugPrint('Diagnostic background prefetch for "$subject" failed: $e');
    }
  }

  /// Bug 2: await the given question's image(s) into cache before the
  /// question is revealed via setState, so the image widget's first render
  /// is a cache hit instead of a live fetch with a spinner. Best-effort —
  /// a short timeout means a slow/broken image never blocks the UI.
  Future<void> _awaitFirstImage(Map<String, dynamic>? question) async {
    if (question == null) return;
    final urls = collectDiagnosticImageUrls(question);
    if (urls.isEmpty) return;
    try {
      await AlochiImageCacheManager()
          .downloadFile(urls.first)
          .timeout(const Duration(seconds: 3));
    } catch (_) {
      // Best-effort — proceed to reveal the question regardless.
    }
  }

  String _questionId(Map<String, dynamic> q) =>
      (q['id'] ?? q['question_id'] ?? '').toString();

  String _questionText(Map<String, dynamic> q) =>
      (q['text'] ?? q['prompt'] ?? q['question_text'] ?? '').toString();

  String _subjectLabel(AppLocalizations l10n, String subject) {
    switch (subject) {
      case 'math':
        return l10n.mathSubjectFull;
      case 'english':
        return l10n.englishSubjectFull;
      default:
        return subject;
    }
  }

  Color _subjectColor(String subject) {
    switch (subject) {
      case 'math':
        return AppColors.math;
      case 'english':
        return AppColors.eng;
      default:
        return AppColors.brand;
    }
  }

  IconData _subjectIcon(String subject) {
    switch (subject) {
      case 'math':
        return Icons.calculate_rounded;
      case 'english':
        return Icons.translate_rounded;
      default:
        return Icons.school_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final q = _question;
    final transition = _transition;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            transition != null
                ? _buildTransitionView(l10n, transition)
                : _loading
                    ? const Center(child: CircularProgressIndicator())
                    : (_error != null || _subjectsEmpty)
                        ? _buildErrorView(l10n)
                        : q == null
                            ? Center(child: Text(l10n.diagnosticNoStudents))
                            : _buildQuestionView(l10n, q),
            // ── Admin-lock pause overlay ─────────────────────────────────
            if (_paused) _buildPauseOverlay(l10n),
          ],
        ),
      ),
    );
  }

  /// Full-screen pause overlay — freezes the countdown underneath and (by
  /// virtue of being on top in the Stack) blocks input too. Mirrors
  /// `TestEngine._buildLockShield`'s look and reuses the same l10n string.
  Widget _buildPauseOverlay(AppLocalizations l10n) {
    return Positioned.fill(
      child: Container(
        color: Colors.black.withValues(alpha: .92),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.pause_circle_filled_rounded,
                color: Colors.white, size: 56),
            const SizedBox(height: 16),
            Text(
              l10n.testLockedByAdmin,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 16,
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildTransitionView(
      AppLocalizations l10n, _SubjectTransition transition) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          l10n.diagnosticSubjectTransitionMessage(
            _subjectLabel(l10n, transition.from),
            _subjectLabel(l10n, transition.to),
          ),
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: AppColors.ink1,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorView(AppLocalizations l10n) {
    // _subjectsEmpty is an expected, calm "not configured yet" state — its
    // own dedicated copy in a neutral/amber info card. Any other _error is a
    // real ApiException/network failure: keep the original red warning
    // treatment so a proctor can still tell "broken" from "nothing to do
    // here" at a glance.
    final title = _subjectsEmpty
        ? l10n.diagnosticSubjectsEmptyTitle
        : (_error ?? l10n.diagnosticSubjectsEmptyTitle);
    final subtitle =
        _subjectsEmpty ? l10n.diagnosticSubjectsEmptySubtitle : null;
    final badgeColor = _subjectsEmpty ? AppColors.amber : AppColors.error;
    final badgeIcon =
        _subjectsEmpty ? Icons.info_outline_rounded : Icons.warning_rounded;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Container(
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 20,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: badgeColor.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(badgeIcon, color: badgeColor, size: 34),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    color: _subjectsEmpty ? AppColors.ink1 : AppColors.error),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.ink2),
                ),
              ],
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      label: Text(l10n.diagnosticGoBack,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.ink2,
                        side: const BorderSide(color: AppColors.border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _retryAction(),
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: Text(l10n.retry,
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.brand,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool get _isFixedVariantAttempt => _isFixedVariant;

  bool get _hasNextSubject {
    final idx = _allSubjects.indexOf(_currentSubject);
    return idx >= 0 && idx < _allSubjects.length - 1;
  }

  Widget _buildQuestionView(AppLocalizations l10n, Map<String, dynamic> q) {
    final imageUrl = (q['image_url'] ?? '').toString().trim();
    final svgVisual = (q['svg_visual'] ?? '').toString().trim();
    final options = extractDiagnosticOptions(q);
    final questionId = _questionId(q);
    final showBottomNav = _isFixedVariantAttempt;
    return Stack(
      children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, 20, 20, showBottomNav ? 110 : 24),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kDockMaxWidth),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DiagnosticHeaderBar(
                      subjectLabel: _subjectLabel(l10n, _currentSubject),
                      subjectIcon: _subjectIcon(_currentSubject),
                      subjectColor: _subjectColor(_currentSubject),
                      position: _position,
                      total: _total,
                      // widget.studentName is intentionally the raw/
                      // unformatted roster name (see
                      // diagnostic_student_select_screen.dart's _start())
                      // so HeartbeatService.startTest() keeps whatever
                      // disambiguating info (patronymic) the backend sends
                      // — format it just for display here.
                      studentName: toDisplayScript(
                          formatStudentDisplayName(widget.studentName),
                          Localizations.localeOf(context)),
                      language: widget.language,
                      remainingSeconds: _remainingSeconds,
                      isFixedVariant: _isFixedVariantAttempt,
                      grade: widget.grade,
                    ),
                    if (_isFixedVariantAttempt) ...[
                      const SizedBox(height: 12),
                      DiagnosticQuestionDots(
                        total: _total,
                        currentIndex: (_position - 1)
                            .clamp(0, _total == 0 ? 0 : _total - 1),
                        answeredIndexes:
                            _answers.keys.map((p) => p - 1).toSet(),
                        onSelectIndex: _jumpTo,
                      ),
                    ],
                    const SizedBox(height: 20),
                    DiagnosticQuestionCard(
                      position: _position,
                      questionText: _questionText(q),
                      imageUrl: imageUrl,
                      svgVisual: svgVisual,
                      flagged: _flaggedQuestionIds.contains(questionId),
                      onToggleFlag: () => setState(() {
                        if (!_flaggedQuestionIds.remove(questionId)) {
                          _flaggedQuestionIds.add(questionId);
                        }
                      }),
                      // Scratchpad is a fixed-variant-only affordance (math
                      // bank) — null on CAT hides the trigger entirely, see
                      // DiagnosticQuestionCard's doc comment.
                      onOpenScratchpad: _isFixedVariantAttempt
                          ? () => setState(() => _scratchpadOpen = true)
                          : null,
                    ),
                    const SizedBox(height: 20),
                    if (_isFixedVariantAttempt)
                      DiagnosticOptionsGrid(
                        options: options,
                        selectedOption: _selectedOption,
                        interactive: !_submitting,
                        onSelect: (key) {
                          setState(() {
                            _selectedOption = key;
                            _answers[_position] = key;
                          });
                          unawaited(_saveProgressIfFixed());
                          // Instant crash-recovery write — SQLite, not the
                          // AttemptStore blob (see DiagnosticAnswerStore's
                          // header comment for why these two stores split).
                          // A local SQLite failure (e.g. a locked disk on
                          // some real device) must never crash/interrupt the
                          // exam flow — same best-effort tolerance as
                          // AttemptStore.save's own try/catch.
                          unawaited(DiagnosticAnswerStore.saveAnswer(
                            attemptId: widget.attemptId,
                            subject: _currentSubject,
                            questionIndex: _position,
                            questionId: questionId,
                            selectedOption: key,
                          ).catchError((e) {
                            debugPrint(
                                'DiagnosticAnswerStore.saveAnswer error: $e');
                          }));
                          HeartbeatService.instance.updateProgress(
                              _position, _total, [], _questionText(q), key);
                          // Live telemetry: reuses the existing proctor
                          // heartbeat channel (already-merged origin/main
                          // fix) + HeartbeatService's existing
                          // reportAnswers() (already used by TestEngine, not
                          // previously called from here).
                          HeartbeatService.instance.reportAnswers(
                            _answers.map((k, v) => MapEntry(k.toString(), v)),
                            _elapsedOnSubject,
                          );
                          _autoAdvance?.cancel();
                          if (!((_position - 1) >= (_total - 1))) {
                            _autoAdvance =
                                Timer(const Duration(milliseconds: 500), () {
                              if (mounted) _jumpTo(_position);
                            });
                          }
                        },
                      )
                    else
                      ...options.map((opt) => DiagnosticOptionCard(
                            label: opt.key,
                            text: opt.text,
                            selected: _selectedOption == opt.key,
                            onTap: _submitting || _selectedOption != null
                                ? () {}
                                : () {
                                    setState(() => _selectedOption = opt.key);
                                    // CAT never populates _answers (each
                                    // pick is submitted immediately, unlike
                                    // the fixed-variant grid's offline-sync
                                    // map above), so only the live
                                    // proctor/spotlight "selected option"
                                    // needs updating here — reportAnswers()
                                    // would just resend a stale/empty map.
                                    HeartbeatService.instance.updateProgress(
                                        _position,
                                        _total,
                                        [],
                                        _questionText(q),
                                        opt.key);
                                    _submit();
                                  },
                          )),
                  ],
                ),
              ),
            ),
          ),
        ),
        const Positioned(top: 12, right: 12, child: SyncStatusBadge()),
        if (_scratchpadOpen)
          Positioned.fill(
            child: DiagnosticScratchpad(
              key: ValueKey(_position),
              onClose: () => setState(() => _scratchpadOpen = false),
            ),
          ),
        if (showBottomNav)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: _kDockMaxWidth),
                child: Container(
                  margin: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.06),
                        blurRadius: 16,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: DiagnosticBottomNav(
                    onPrevious:
                        _position <= 1 ? null : () => _jumpTo(_position - 2),
                    onNext: () => _jumpTo(_position),
                    onFinish: _isFixedVariant
                        ? _confirmAndFinishPackage
                        : _finishTest,
                    onEarlyFinish: _onEarlyFinishTap,
                    isLast: (_position - 1) >= (_total - 1),
                    submitting: _submitting,
                    hasNextSubject: _hasNextSubject,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
