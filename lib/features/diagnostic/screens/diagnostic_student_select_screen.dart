// lib/features/diagnostic/screens/diagnostic_student_select_screen.dart
//
// Diagnostic kiosk flow — step 3: search + 2-col avatar-card grid + floating
// CTA, pattern copied (never imported) from
// lib/features/session/student_entry_screen.dart. Shows ALL candidates in
// the class regardless of finished status (decision #5 in the plan) — a
// repeat attempt surfaces the CAT engine's own "already finished" error.
// `parent_phone` is never requested/rendered here (the backend never sends
// it for this endpoint).
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart' show ApiException;
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_kiosk_api.dart';
import '../utils/diagnostic_image_prefetch.dart';
import '../widgets/diagnostic_widgets.dart';
import '../../../core/utils/student_name_formatter.dart';

/// Fixed contract with the alochi-unit-tests Vercel frontend's
/// `/kiosk-entry` route: it reads `code` (an opaque exchange code, per the
/// S-003 fix) off the query string, redeems it for a token itself, and
/// auto-logs the student in.
const String _kWebTestEntryUrl =
    'https://alochi-unit-tests.vercel.app/kiosk-entry';

/// `_peekAndCache`ning ichki natijasi — status-hisoblash uchun.
enum _PeekOutcome { cached, skippedCat, failed }

class DiagnosticStudentSelectScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;
  final String schoolCode;
  final String classLabel;
  final String language;
  final bool hasWebTest;
  final String webTestKey;

  /// Test-only overrides — default to the real [diagnosticKioskApi] methods.
  /// Mirrors the *Override convention already used in
  /// diagnostic_test_runner_screen.dart, extended to this screen so the
  /// Task 2 background-prefetch-on-tap flow (and the Task 1 Enter shortcut
  /// that depends on a selected student) is testable without real HTTP.
  final Future<(List<Map<String, dynamic>>, bool)> Function(
      String schoolId, String classLabel)? listStudentsOverride;
  final Future<Map<String, dynamic>> Function(int grade, {String language})?
      availableSubjectsOverride;
  final Future<Map<String, dynamic>> Function(
      {required String attemptId,
      required String subject})? peekSubjectOverride;

  const DiagnosticStudentSelectScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
    this.schoolCode = '',
    required this.classLabel,
    required this.language,
    this.hasWebTest = false,
    this.webTestKey = '',
    this.listStudentsOverride,
    this.availableSubjectsOverride,
    this.peekSubjectOverride,
  });

  @override
  State<DiagnosticStudentSelectScreen> createState() =>
      _DiagnosticStudentSelectScreenState();
}

class _DiagnosticStudentSelectScreenState
    extends State<DiagnosticStudentSelectScreen> {
  bool _loading = true;
  bool _starting = false;
  String? _error;
  List<Map<String, dynamic>> _students = [];
  bool _fromCache = false;
  Map<String, dynamic>? _selected;
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// Keyboard-focus node for the Enter/NumpadEnter shortcut (Task 1) — must
  /// be focused for `CallbackShortcuts` bindings to fire.
  final _focusNode = FocusNode();

  /// Task 2: every subject's `kiosk/peek/` result for the currently-tapped
  /// student's attempt, keyed by `attempt_id` then subject — threaded into
  /// `DiagnosticTestRunnerScreen.prefetchedSubjects` on start so even the
  /// FIRST subject can begin from a warm cache. Peek is side-effect-free
  /// (see diagnostic_kiosk_api.dart), so unlike a real start-attempt call it
  /// is safe to fire for every subject up front, not just the current one.
  final Map<String, Map<String, Map<String, dynamic>>> _peekCache = {};

  /// The exact subject list `_prefetchSubjectsForStudent` already resolved
  /// via `availableSubjects`, keyed by attempt_id — threaded into
  /// `DiagnosticTestRunnerScreen.prefetchedAllSubjects` so a fresh attempt
  /// can start from the cached [_peekCache] package even when the runner's
  /// own live `availableSubjects` re-fetch fails offline (see that screen's
  /// `_bootstrap` catch block).
  final Map<String, List<String>> _allSubjectsCache = {};

  /// Task: har bir o'quvchining fixed-variant fanlari bo'yicha offline-
  /// tayyorlik holati. Yozuv yo'q = hali umuman urinilmagan (belgi
  /// ko'rsatilmaydi).
  final Map<String, StudentPrefetchStatus> _studentStatus = {};

  /// Shu o'quvchida kamida bitta CAT/adaptiv (fixed_variant==false) fan
  /// borligi — status-hisobiga kirmaydi, alohida neytral belgi bilan
  /// ko'rsatiladi.
  final Map<String, bool> _studentHasOnlineOnlySubject = {};

  /// Har bir o'quvchining joriy prefetch operatsiyasi — "Boshlash" tugmasi
  /// va bulk-yuklash shu Future'ni kutishi mumkin (status enumning o'zi
  /// kutilmaydigan, shuning uchun alohida saqlanadi).
  final Map<String, Future<void>> _prefetchInFlight = {};

  bool _prefetchingAll = false;
  int _prefetchedCount = 0;
  bool _waitingForPrefetch = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() => _query = _searchCtrl.text.trim().toLowerCase());
    });
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// Task 2: background, best-effort warm-up fired the moment a student
  /// card is tapped — never awaited by the tap handler, never surfaces an
  /// error to the UI. Peeks EVERY subject the student's grade actually has
  /// (via `availableSubjects`, the same call the runner screen's own
  /// `_bootstrap` makes) and caches only the fixed-variant ones (a `false`
  /// `fixed_variant` means nothing to prefetch for that subject).
  Future<void> _prefetchSubjectsForStudent(Map<String, dynamic> student) async {
    final attemptId = (student['attempt_id'] ?? '').toString();
    if (attemptId.isEmpty) return;
    final grade =
        (student['session_grade'] as num?)?.toInt() ?? _gradeFromClassLabel();
    if (mounted) {
      setState(() => _studentStatus[attemptId] = StudentPrefetchStatus.loading);
    }
    try {
      final availableSubjects = widget.availableSubjectsOverride ??
          diagnosticKioskApi.availableSubjects;
      final subjectsResp =
          await availableSubjects(grade, language: widget.language);
      final subjects = (subjectsResp['subjects'] as List?)
              ?.map((e) => e.toString())
              .where((e) => e.isNotEmpty)
              .toList() ??
          const <String>[];
      _allSubjectsCache[attemptId] = subjects;
      var cachedCount = 0;
      var anyFailed = false;
      var anyOnlineOnly = false;
      // Ketma-ket (parallel emas) — 20-30 o'quvchilik sinf uchun bulk-
      // yuklashda tarmoq/throttle xavfini oshirmaslik uchun ataylab shunday
      // (avvalgi seansda tasdiqlangan qaror).
      for (final subject in subjects) {
        final outcome = await _peekAndCache(attemptId, subject);
        switch (outcome) {
          case _PeekOutcome.cached:
            cachedCount++;
            break;
          case _PeekOutcome.skippedCat:
            anyOnlineOnly = true;
            break;
          case _PeekOutcome.failed:
            anyFailed = true;
            break;
        }
      }
      if (mounted) {
        setState(() {
          _studentHasOnlineOnlySubject[attemptId] = anyOnlineOnly;
          if (anyFailed) {
            _studentStatus[attemptId] = StudentPrefetchStatus.error;
          } else if (cachedCount > 0) {
            _studentStatus[attemptId] = StudentPrefetchStatus.ready;
          } else {
            // Fanlarning barchasi CAT/adaptiv — hech narsa keshlanmadi,
            // "tayyor" deb da'vo qilib bo'lmaydi.
            _studentStatus.remove(attemptId);
          }
        });
      }
    } catch (e) {
      debugPrint('Diagnostic subject-prefetch (availableSubjects) failed: $e');
      if (mounted) {
        setState(() => _studentStatus[attemptId] = StudentPrefetchStatus.error);
      }
    }
  }

  Future<_PeekOutcome> _peekAndCache(String attemptId, String subject) async {
    try {
      final peekSubject =
          widget.peekSubjectOverride ?? diagnosticKioskApi.peekSubject;
      final resp = await peekSubject(attemptId: attemptId, subject: subject);
      if (resp['fixed_variant'] == false) return _PeekOutcome.skippedCat;
      _peekCache.putIfAbsent(attemptId, () => {})[subject] = resp;
      final questions = (resp['questions'] as List?)
          ?.whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (questions != null && questions.isNotEmpty) {
        prefetchDiagnosticImages(questions);
      }
      return _PeekOutcome.cached;
    } catch (e) {
      debugPrint('Diagnostic peek prefetch for "$subject" failed: $e');
      return _PeekOutcome.failed;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listStudents =
          widget.listStudentsOverride ?? diagnosticKioskApi.listStudents;
      final (students, fromCache) =
          await listStudents(widget.schoolId, widget.classLabel);
      if (!mounted) return;
      setState(() {
        _students = students;
        _fromCache = fromCache;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_query.isEmpty) return _students;
    final query = cyrillicToLatinUzbek(_query).toLowerCase();
    return _students
        .where((s) => cyrillicToLatinUzbek((s['student_name'] ?? '').toString())
            .toLowerCase()
            .contains(query))
        .toList();
  }

  /// Grade is derived from the class label's leading digits (e.g. "4-A" → 4).
  int _gradeFromClassLabel() {
    final match = RegExp(r'^(\d+)').firstMatch(widget.classLabel);
    return int.tryParse(match?.group(1) ?? '') ?? 1;
  }

  Future<void> _start() async {
    final s = _selected;
    if (s == null) return;
    if (!widget.hasWebTest) {
      _startCat(s);
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _TestTypeSheet(l10n: l10n),
    );
    if (!mounted || choice == null) return;
    if (choice == 'web') {
      _startWebTest(s);
    } else {
      _startCat(s);
    }
  }

  void _startCat(Map<String, dynamic> s) {
    final attemptId = (s['attempt_id'] ?? '').toString();
    context.push('/diagnostic_test_runner', extra: {
      'attemptId': attemptId,
      // Raw (unformatted) name on purpose — this flows into
      // HeartbeatService.startTest() and becomes the identity shown in the
      // live monitoring/proctoring feed. Stripping the patronymic there
      // would make same-name classmates indistinguishable to the teacher.
      // The roster card above already shows the cleaned name; the runner
      // screen formats it again for its own on-screen display.
      'studentName': (s['student_name'] ?? '').toString(),
      'grade': (s['session_grade'] as num?)?.toInt() ?? _gradeFromClassLabel(),
      'schoolCode': widget.schoolCode,
      'language': widget.language,
      // Display-only, for DiagnosticHistoryDb (Task 4).
      'schoolName': widget.schoolName,
      'classLabel': widget.classLabel,
      // Task 2: whatever this student's subjects were already peeked into
      // while they sat selected on this screen (may be empty/absent if the
      // peeks are still in flight or all came back non-fixed-variant).
      'prefetchedSubjects': _peekCache[attemptId] ?? const {},
      // Same "may still be in flight" caveat as prefetchedSubjects above —
      // an empty/absent list just falls back to the runner's own live fetch.
      'prefetchedAllSubjects': _allSubjectsCache[attemptId] ?? const <String>[],
    });
  }

  Future<void> _startWebTest(Map<String, dynamic> s) async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _starting = true);
    try {
      final exchangeCode = await diagnosticKioskApi.webTestStart(
        attemptId: (s['attempt_id'] ?? '').toString(),
        testKey: widget.webTestKey,
      );
      final uri = Uri.parse(_kWebTestEntryUrl)
          .replace(queryParameters: {'code': exchangeCode});
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.helpLinkOpenError),
          backgroundColor: AppColors.error,
        ));
      }
    } on ApiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.message),
          backgroundColor: AppColors.error,
        ));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(l10n.helpLinkOpenError),
          backgroundColor: AppColors.error,
        ));
      }
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filtered = _filtered;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (_selected != null && !_starting) _start();
        },
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () {
          if (_selected != null && !_starting) _start();
        },
      },
      child: Focus(
        autofocus: true,
        focusNode: _focusNode,
        child: Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : SingleChildScrollView(
                          padding: const EdgeInsets.only(
                              top: 90, bottom: 140, left: 16, right: 16),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 768),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  DiagnosticStepIndicator(
                                      l10n.diagnosticStep(3)),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.diagnosticWhoTakesTest,
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: -0.5,
                                      color: AppColors.ink1,
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  TextField(
                                    controller: _searchCtrl,
                                    decoration: InputDecoration(
                                      hintText: l10n.searchStudents,
                                      prefixIcon: const Icon(
                                          Icons.search_rounded,
                                          size: 20),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  if (_error == null && _fromCache)
                                    const DiagnosticOfflineBadge(),
                                  if (_error != null)
                                    Container(
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: AppColors.errorMuted,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                            color: AppColors.error
                                                .withValues(alpha: 0.2)),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.warning_rounded,
                                              color: AppColors.error, size: 20),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(_error!,
                                                style: const TextStyle(
                                                    color: AppColors.error,
                                                    fontSize: 14,
                                                    fontWeight:
                                                        FontWeight.w500)),
                                          ),
                                          TextButton(
                                            onPressed: _load,
                                            child: Text(l10n.retry),
                                          ),
                                        ],
                                      ),
                                    )
                                  else if (filtered.isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 40),
                                      child: Text(
                                        l10n.diagnosticNoStudents,
                                        style: const TextStyle(
                                            fontSize: 16,
                                            color: AppColors.ink3),
                                      ),
                                    )
                                  else
                                    GridView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      gridDelegate:
                                          const SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: 2,
                                        mainAxisSpacing: 8,
                                        crossAxisSpacing: 8,
                                        childAspectRatio: 4.2,
                                      ),
                                      itemCount: filtered.length,
                                      itemBuilder: (context, index) {
                                        final student = filtered[index];
                                        final attemptId =
                                            (student['attempt_id'] ?? '')
                                                .toString();
                                        return DiagnosticStudentCard(
                                          name: formatStudentDisplayName(
                                              (student['student_name'] ?? '')
                                                  .toString()),
                                          isSelected: _selected == student,
                                          status: _studentStatus[attemptId],
                                          hasOnlineOnlySubject:
                                              _studentHasOnlineOnlySubject[
                                                      attemptId] ??
                                                  false,
                                          onRetryTap: () {
                                            final future =
                                                _prefetchSubjectsForStudent(
                                                    student);
                                            if (attemptId.isNotEmpty) {
                                              _prefetchInFlight[attemptId] =
                                                  future;
                                            }
                                            unawaited(future);
                                          },
                                          onTap: () {
                                            setState(() => _selected = student);
                                            final future =
                                                _prefetchSubjectsForStudent(
                                                    student);
                                            if (attemptId.isNotEmpty) {
                                              _prefetchInFlight[attemptId] =
                                                  future;
                                            }
                                            unawaited(future);
                                          },
                                        );
                                      },
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                ),
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 600),
                      child: DiagnosticTopBar(title: widget.classLabel),
                    ),
                  ),
                ),
                Positioned(
                  bottom: 20,
                  left: 20,
                  right: 20,
                  child: DiagnosticBottomCta(
                    label: l10n.diagnosticStartTest,
                    enabled: _selected != null && !_starting,
                    loading: _starting,
                    onTap: _start,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "CAT test" vs "Veb-test" picker, shown only for classes with
/// `has_web_test: true`. Pops `'cat'` or `'web'`.
class _TestTypeSheet extends StatelessWidget {
  final AppLocalizations l10n;
  const _TestTypeSheet({required this.l10n});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text(
              l10n.diagnosticChooseTestType,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.ink1,
              ),
            ),
            const SizedBox(height: 12),
            _TestTypeOption(
              icon: Icons.bolt_rounded,
              label: l10n.diagnosticCatTestOption,
              onTap: () => Navigator.of(context).pop('cat'),
            ),
            const SizedBox(height: 8),
            _TestTypeOption(
              icon: Icons.public_rounded,
              label: l10n.diagnosticWebTestOption,
              onTap: () => Navigator.of(context).pop('web'),
            ),
          ],
        ),
      ),
    );
  }
}

class _TestTypeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _TestTypeOption(
      {required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.pageBg,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Icon(icon, size: 20, color: AppColors.brand),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.ink1,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppColors.ink3),
            ],
          ),
        ),
      ),
    );
  }
}
