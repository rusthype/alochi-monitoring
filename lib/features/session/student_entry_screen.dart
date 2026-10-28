import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/db/test_cache.dart';
import '../../core/offline/lan_client_session.dart' show isOfflineModeOpen;
import '../../core/offline/offline_session.dart';
import '../../core/services/roster_done_store.dart';
import '../../core/services/test_catalog_service.dart';
import '../../core/services/toast_service.dart';
import '../../shared/theme/app_theme.dart';
import '../diagnostic/widgets/diagnostic_widgets.dart'
    show StudentPrefetchStatus, StudentStatusBadge;
import 'runner_dispatch.dart';
import 'test_session.dart';
import '../../core/widgets/skeleton.dart';

class StudentEntryScreen extends StatefulWidget {
  final TestSession session;
  final Map<String, dynamic>? preselectedGroup;

  /// Test seam for the image-readiness badge; defaults to the global service.
  @visibleForTesting
  final TestCatalogService? catalog;

  const StudentEntryScreen({
    super.key,
    required this.session,
    this.preselectedGroup,
    this.catalog,
  });

  @override
  State<StudentEntryScreen> createState() => _StudentEntryScreenState();
}

class _StudentEntryScreenState extends State<StudentEntryScreen> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  final _firstFocus = FocusNode();
  final _lastFocus = FocusNode();
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';
  int? _grade;
  String? _err;
  bool _launching = false;

  // Variant-image preparation: when a student is selected, ONLY that
  // student's variant images are downloaded into the persistent store, so
  // "Start" enters with zero downloading.
  int _prepToken = 0; // bumped on every (re)start/cancel -> stale results ignored
  bool _preparing = false;
  String? _prepProgress; // "done/total" while downloading, else null
  String? _preparedFor; // studentId whose variant images are ready
  int? _preparedVariant; // the variant that was prepared (and will be launched)
  // Variant drawn per student so re-selecting a student never re-draws.
  final Map<String, int> _drawnVariant = {};
  List<Map<String, dynamic>> _groups = [];
  Map<String, dynamic>? _selectedGroup;
  bool _loadingGroups = true;
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _selectedStudent;
  bool _loadingStudents = false;
  // Roster ids that already finished this test: pack chain + backend `done`
  // flag + this kiosk's own local record (RosterDoneStore).
  Set<String> _done = {};
  // Test-level image readiness badge; null = show nothing (pack/LAN, no cache).
  StudentPrefetchStatus? _testStatus;
  int _statusToken = 0;

  TestCatalogService get _catalog => widget.catalog ?? testCatalogService;

  static String _rosterKey(Map<String, dynamic> s) =>
      (s['student_code'] ?? s['id'] ?? '').toString();

  String get _selectedStudentId => (_selectedStudent?['student_code'] ??
          _selectedStudent?['id'] ??
          '')
      .toString();

  bool get _rosterActive =>
      _selectedGroup != null && (_loadingStudents || _students.isNotEmpty);

  bool get _canStart {
    if (_launching || _preparing) return false;
    // A roster student can start ONLY once every image of their variant is on
    // disk; after a failed prepare the button stays blocked until a re-tap on
    // the student succeeds. Never a partial start.
    if (_selectedStudent != null) return _preparedFor == _selectedStudentId;
    if (_selectedGroup != null && (_loadingStudents || _students.isNotEmpty)) {
      return false;
    }
    return _firstCtrl.text.trim().isNotEmpty &&
        _lastCtrl.text.trim().isNotEmpty;
  }

  void _onTextChanged() => setState(() {});

  @override
  void initState() {
    super.initState();
    _firstCtrl.addListener(_onTextChanged);
    _lastCtrl.addListener(_onTextChanged);
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text.trim().toLowerCase();
      });
    });
    _loadGroups();
  }

  Future<void> _loadGroups() async {
    if (widget.preselectedGroup != null) {
      setState(() {
        _groups = [widget.preselectedGroup!];
        _selectedGroup = widget.preselectedGroup;
        _loadingGroups = false;
      });
      await _loadStudents();
      return;
    }
    try {
      final g = await api.fetchGroups(widget.session.schoolCode);
      if (!mounted) return;
      setState(() {
        _groups = g;
        _loadingGroups = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingGroups = false;
      });
    }
  }

  Future<void> _loadStudents() async {
    final groupId = (_selectedGroup?['id'] ?? '').toString();
    if (groupId.isEmpty) return;
    _cancelPrepare();
    setState(() {
      _loadingStudents = true;
      _students = [];
      _selectedStudent = null;
      _err = null;
    });
    try {
      final testKey = widget.session.testKey;
      final s = await api.fetchStudents(groupId, testKey: testKey);
      final done = <String>{
        ...await OfflinePackSession.current?.finishedStudentIds(testKey) ??
            <String>{},
        ...await RosterDoneStore.load(testKey),
        // Old backend: no `done` field -> nothing added.
        for (final st in s)
          if (st['done'] == true) _rosterKey(st),
      };
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _students = s;
        _done = done;
        _loadingStudents = false;
        _err = s.isEmpty ? l10n.noStudentsInGroup : null;
      });
      unawaited(_refreshTestStatus());
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _loadingStudents = false;
        _err = l10n.loadStudentsError;
      });
    }
  }

  /// Test-level "images on disk" badge: loading while the background prefetch
  /// runs, then ready (all variants complete) or error (retry on tap).
  Future<void> _refreshTestStatus() async {
    final key = widget.session.testKey;
    final token = ++_statusToken;
    StudentPrefetchStatus? next;
    try {
      final cached = isOfflineModeOpen ? null : await TestCache.get(key);
      if (cached != null) {
        final job = _catalog.backgroundJob(key);
        if (job != null) {
          if (!mounted || token != _statusToken) return;
          setState(() => _testStatus = StudentPrefetchStatus.loading);
          await job;
        }
        next = await _catalog.testImagesComplete(cached)
            ? StudentPrefetchStatus.ready
            : StudentPrefetchStatus.error;
      }
    } catch (e) {
      debugPrint('StudentEntryScreen: test status error: $e');
      next = StudentPrefetchStatus.error;
    }
    if (!mounted || token != _statusToken) return;
    setState(() => _testStatus = next);
  }

  Future<void> _retryTestPrefetch() async {
    final key = widget.session.testKey;
    final cached = await TestCache.get(key);
    if (cached == null || !mounted) return;
    setState(() => _testStatus = StudentPrefetchStatus.loading);
    unawaited(_catalog.backgroundPrefetch(key, cached));
    await _refreshTestStatus();
  }

  @override
  void dispose() {
    _firstCtrl.removeListener(_onTextChanged);
    _lastCtrl.removeListener(_onTextChanged);
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    _firstFocus.dispose();
    _lastFocus.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _cancelPrepare() {
    _prepToken++;
    _preparing = false;
    _prepProgress = null;
    _preparedFor = null;
    _preparedVariant = null;
  }

  /// Downloads ONLY [studentId]'s variant images (plus shared ones) into the
  /// persistent store. Already-stored images cost nothing (no network).
  /// Returns true when ready; on failure shows the error toast and returns
  /// false (the student re-taps / presses Start to retry). Results of a
  /// superseded prepare (another student tapped meanwhile) are ignored.
  Future<bool> _prepareFor(String studentId) async {
    if (_preparedFor == studentId && !_preparing) return true;
    final token = ++_prepToken;
    setState(() {
      _preparing = true;
      _prepProgress = null;
      _preparedFor = null;
      _preparedVariant = null;
    });
    var ok = false;
    int? variant;
    Map<String, dynamic>? cached;
    var cacheReadable = true;
    try {
      cached = await TestCache.get(widget.session.testKey);
    } catch (e) {
      // Unreadable cache: nothing to prepare here; launchRunner reports it.
      cacheReadable = false;
      debugPrint('StudentEntryScreen: cache read error: $e');
    }
    try {
      if (!cacheReadable || cached == null) {
        // Pack/LAN mode: launchRunner loads the test itself; nothing to fetch.
        ok = true;
      } else {
        variant = await previewAttemptVariant(cached,
            testKey: widget.session.testKey,
            studentId: studentId,
            drawn: _drawnVariant[studentId]);
        _drawnVariant[studentId] = variant;
        ok = await _catalog.ensureVariantImages(cached, variant,
            onProgress: (done, total) {
          if (mounted && token == _prepToken) {
            setState(() => _prepProgress = '$done/$total');
          }
        });
      }
    } catch (e) {
      debugPrint('StudentEntryScreen: prepare($studentId) error: $e');
    }
    if (!mounted || token != _prepToken) return false;
    setState(() {
      _preparing = false;
      _prepProgress = null;
      if (ok) {
        _preparedFor = studentId;
        _preparedVariant = variant;
      }
    });
    if (ok && _testStatus == StudentPrefetchStatus.error) {
      unawaited(_refreshTestStatus());
    }
    if (!ok) {
      ToastService.showError(
          context, AppLocalizations.of(context)!.downloadError);
    }
    return ok;
  }

  Future<void> _startTest() async {
    final l10n = AppLocalizations.of(context)!;
    String firstName;
    String lastName;
    String studentId;

    if (_selectedStudent != null) {
      firstName = (_selectedStudent!['first_name'] ?? '').toString();
      lastName = (_selectedStudent!['last_name'] ?? '').toString();
      if (firstName.isEmpty && lastName.isEmpty) {
        final parts = (_selectedStudent!['name'] ?? '').toString().split(' ');
        lastName = parts.isNotEmpty ? parts.first : '';
        firstName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
      studentId =
          (_selectedStudent!['student_code'] ?? _selectedStudent!['id'] ?? '')
              .toString();
    } else {
      final first = _firstCtrl.text.trim();
      final last = _lastCtrl.text.trim();
      if (first.isEmpty || last.isEmpty) {
        setState(() => _err = l10n.enterNameError);
        return;
      }
      firstName = first;
      lastName = last;
      studentId = '';
    }

    int grade;
    String groupName;
    String groupId;
    if (_groups.isNotEmpty) {
      if (_selectedGroup == null) {
        setState(() => _err = l10n.selectGroup);
        return;
      }
      grade = widget.session.testGrade;
      groupName = (_selectedGroup!['name'] ?? '').toString();
      groupId = (_selectedGroup!['id'] ?? '').toString();
    } else {
      if (_grade == null) {
        setState(() => _err = l10n.selectGrade);
        return;
      }
      grade = _grade!;
      groupName = '';
      groupId = '';
    }
    if (_selectedStudent != null && _done.contains(studentId)) {
      if (!await _confirmRetake() || !mounted) return;
    }
    setState(() {
      _err = null;
      _launching = true;
    });
    // Normally already prepared when the student was tapped; manual-name
    // entry (no roster) prepares here, with progress on the start button.
    if (_preparedFor != studentId && !await _prepareFor(studentId)) {
      if (mounted) setState(() => _launching = false);
      return;
    }
    if (!mounted) return;
    await launchRunner(
      context,
      session: widget.session,
      firstName: firstName,
      lastName: lastName,
      studentGrade: grade,
      groupName: groupName,
      groupId: groupId,
      studentId: studentId,
      preparedVariant: _preparedVariant,
    );
    if (!mounted) return;
    // Stay on this roster (same group, same test) for the next student: also
    // after a launch failure (locked / not in cache), which just toasts.
    setState(() => _launching = false);
    if (_selectedGroup != null) {
      await _loadStudents(); // clears selection + prepared state, refreshes done
    } else {
      // Group-less path: no roster to reload, reset the entry by hand.
      _cancelPrepare();
      _firstCtrl.clear();
      _lastCtrl.clear();
      setState(() => _err = null);
    }
  }

  Future<bool> _confirmRetake() async {
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.diagnosticRetakeTitle),
        content: Text(l10n.testRetakeBody),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: Text(l10n.cancel)),
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text(l10n.diagnosticRetakeConfirm)),
        ],
      ),
    );
    return ok == true;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isSmall = MediaQuery.of(context).size.width < 800;

    final filteredStudents = _searchQuery.isEmpty
        ? _students
        : _students
            .where((s) => (s['name'] ?? '')
                .toString()
                .toLowerCase()
                .contains(_searchQuery))
            .toList();

    return Shortcuts(
      shortcuts: <ShortcutActivator, Intent>{
        LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
            const SearchStudentsIntent(),
        LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK):
            const SearchStudentsIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          SearchStudentsIntent: CallbackAction<SearchStudentsIntent>(
            onInvoke: (SearchStudentsIntent intent) {
              if (_rosterActive && _students.isNotEmpty) {
                _searchFocus.requestFocus();
              }
              return null;
            },
          ),
        },
        child: Scaffold(
          backgroundColor: AppColors.pageBg,
          body: Stack(
            children: [
              // Background noise
              Positioned.fill(
                child: Opacity(
                  opacity: 0.03,
                  child: Image.asset(
                    'assets/noise.png', // Fallback, doesn't matter if absent
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const SizedBox(),
                  ),
                ),
              ),


              SafeArea(
                child: CustomScrollView(
                  key: PageStorageKey('student_entry_scroll_${_selectedGroup?['id']}'),
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.only(
                          top: isSmall ? 60 : 80,
                          left: isSmall ? 16 : 20,
                          right: isSmall ? 16 : 20),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                const SizedBox(height: 12),
                                Text(
                                  l10n.whoTakesTest,
                                  style: TextStyle(
                                    fontSize: isSmall ? 28 : 36,
                                    fontWeight: FontWeight.w900,
                                    height: 1.1,
                                    letterSpacing: -1,
                                    color: AppColors.ink1,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                if (widget.preselectedGroup == null) ...[
                                  if (_groups.isNotEmpty)
                                    Text(
                                      l10n.selectGroup,
                                      style: const TextStyle(
                                          fontSize: 16, color: AppColors.ink2),
                                    ),
                                  const SizedBox(height: 16),
                                  if (_loadingGroups)
                                    const Skeleton(height: 48, borderRadius: 12)
                                  else if (_groups.isNotEmpty)
                                    Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: _groups.map((g) {
                                      final selected = _selectedGroup == g;
                                      final name = (g['name'] ?? '').toString();
                                      return Semantics(
                                        button: true,
                                        label: name,
                                        child: GestureDetector(
                                          onTap: () {
                                            _cancelPrepare();
                                            setState(() {
                                              _selectedGroup = g;
                                              _selectedStudent = null;
                                              _searchCtrl.clear();
                                              _searchQuery = '';
                                            });
                                            _loadStudents();
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 160),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 12),
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? AppColors.brand
                                                      .withValues(alpha: 0.1)
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(10),
                                              border: Border.all(
                                                color: selected
                                                    ? AppColors.brand
                                                    : AppColors.border,
                                              ),
                                            ),
                                            child: Text(
                                              name,
                                              style: TextStyle(
                                                color: selected
                                                    ? AppColors.brand
                                                    : AppColors.ink1,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                                if (_selectedGroup != null) ...[
                                  if (widget.preselectedGroup == null)
                                    const SizedBox(height: 20),
                                  if (!_loadingStudents && _students.isNotEmpty)
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: TextField(
                                        controller: _searchCtrl,
                                        focusNode: _searchFocus,
                                        decoration: InputDecoration(
                                          hintText: l10n.searchStudents,
                                          prefixIcon: const Icon(Icons.search),
                                          filled: true,
                                          fillColor: Colors.white,
                                          contentPadding:
                                              const EdgeInsets.symmetric(
                                                  horizontal: 14, vertical: 12),
                                          border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            borderSide: const BorderSide(
                                                color: AppColors.border),
                                          ),
                                        ),
                                      ),
                                    ),
                                ] else if (_groups.isEmpty) ...[
                                  Text(l10n.selectGrade,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14)),
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [1, 2, 3, 4].map((n) {
                                      final selected = _grade == n;
                                      return Expanded(
                                        child: Padding(
                                          padding:
                                              const EdgeInsets.only(right: 8),
                                          child: Semantics(
                                            button: true,
                                            label: l10n.gradeN(n),
                                            child: GestureDetector(
                                              onTap: () =>
                                                  setState(() => _grade = n),
                                              child: AnimatedContainer(
                                                duration: const Duration(
                                                    milliseconds: 160),
                                                height: 48,
                                                decoration: BoxDecoration(
                                                  color: selected
                                                      ? AppColors.brand
                                                          .withValues(alpha: 0.1)
                                                      : Colors.white,
                                                  borderRadius:
                                                      BorderRadius.circular(10),
                                                  border: Border.all(
                                                    color: selected
                                                        ? AppColors.brand
                                                        : AppColors.border,
                                                  ),
                                                ),
                                                alignment: Alignment.center,
                                                child: Text(
                                                  '$n',
                                                  style: TextStyle(
                                                    color: selected
                                                        ? AppColors.brand
                                                        : AppColors.ink1,
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (_selectedGroup != null)
                      SliverPadding(
                        padding: EdgeInsets.only(
                            left: isSmall ? 16 : 20, right: isSmall ? 16 : 20),
                        sliver: SliverLayoutBuilder(
                          builder: (context, constraints) {
                            final double availableWidth =
                                constraints.crossAxisExtent;
                            final double horizontalPadding =
                                availableWidth > 600
                                    ? (availableWidth - 600) / 2
                                    : 0.0;
                            final int crossAxisCount =
                                (availableWidth - horizontalPadding * 2) > 400
                                    ? 2
                                    : 1;
                            // Base cell height (56) is tuned for default text
                            // scale. Grow it with the system font scale so
                            // large accessibility text doesn't get clipped.
                            final double textScale = MediaQuery.textScalerOf(
                                    context)
                                .scale(14) /
                                14;
                            final double itemHeight =
                                56 * textScale.clamp(1.0, 1.6);
                            final double contentWidth =
                                availableWidth - horizontalPadding * 2;
                            final double itemWidth = crossAxisCount > 0
                                ? (contentWidth - (crossAxisCount - 1) * 8) /
                                    crossAxisCount
                                : contentWidth;
                            final double childAspectRatio =
                                itemWidth / itemHeight;

                            if (_loadingStudents) {
                              return SliverPadding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: horizontalPadding),
                                sliver: SliverGrid(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: childAspectRatio,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) => const Skeleton(
                                        height: 56, borderRadius: 12),
                                    childCount: 6,
                                  ),
                                ),
                              );
                            } else if (_students.isNotEmpty) {
                              return SliverPadding(
                                padding: EdgeInsets.symmetric(
                                    horizontal: horizontalPadding),
                                sliver: SliverGrid(
                                  gridDelegate:
                                      SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: crossAxisCount,
                                    mainAxisSpacing: 8,
                                    crossAxisSpacing: 8,
                                    childAspectRatio: childAspectRatio,
                                  ),
                                  delegate: SliverChildBuilderDelegate(
                                    (context, index) {
                                      final student = filteredStudents[index];
                                      final name = (student['name'] ?? '')
                                          .toString();
                                      final initial = name.isNotEmpty
                                          ? name[0].toUpperCase()
                                          : '?';
                                      return _StudentCard(
                                        name: name,
                                        avatarLetter: initial,
                                        isSelected: _selectedStudent == student,
                                        isDone:
                                            _done.contains(_rosterKey(student)),
                                        testStatus: _testStatus,
                                        onRetryStatus: _retryTestPrefetch,
                                        onTap: () {
                                          setState(
                                              () => _selectedStudent = student);
                                          _prepareFor((student['student_code'] ??
                                                  student['id'] ??
                                                  '')
                                              .toString());
                                        },
                                      );
                                    },
                                    childCount: filteredStudents.length,
                                  ),
                                ),
                              );
                            } else {
                              return SliverToBoxAdapter(
                                child: Center(
                                  child: Padding(
                                    padding:
                                        const EdgeInsets.symmetric(vertical: 8),
                                    child: TextButton.icon(
                                      onPressed: _loadStudents,
                                      icon: const Icon(Icons.refresh_rounded,
                                          size: 16),
                                      label: Text(l10n.retry),
                                    ),
                                  ),
                                ),
                              );
                            }
                          },
                        ),
                      ),
                    SliverPadding(
                      padding: EdgeInsets.only(
                          left: isSmall ? 16 : 20,
                          right: isSmall ? 16 : 20,
                          bottom: 140),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 600),
                            child: Column(
                              children: [
                                if (_err != null) ...[
                                  const SizedBox(height: 12),
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: AppColors.err.withValues(alpha: 0.08),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.warning_rounded,
                                            color: AppColors.err, size: 16),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            _err!,
                                            style: const TextStyle(
                                                color: AppColors.err,
                                                fontSize: 13),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Floating Navbar
              Positioned(
                top: MediaQuery.of(context).padding.top + (isSmall ? 8 : 16),
                left: isSmall ? 8 : 16,
                right: isSmall ? 8 : 16,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: _DoubleBezel(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Semantics(
                            button: true,
                            label: l10n.backBtn,
                            child: GestureDetector(
                              onTap: () {
                                if (context.canPop()) {
                                  context.pop();
                                } else {
                                  context.go('/');
                                }
                              },
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: const BoxDecoration(
                                  color: AppColors.pageBg,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.arrow_back_rounded,
                                    size: 18, color: AppColors.brand),
                              ),
                            ),
                          ),
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                        color: AppColors.brand,
                                        shape: BoxShape.circle)),
                                const SizedBox(width: 6),
                                Flexible(
                                  child: Text(
                                    widget.session.schoolLabel.isEmpty
                                        ? l10n.generalTests.toUpperCase()
                                        : widget.session.schoolLabel
                                            .toUpperCase(),
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        color: AppColors.brand,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        letterSpacing: 1),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 44), // Spacer for centering
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Fade
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                height: 140,
                child: IgnorePointer(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.pageBg.withValues(alpha: 0),
                          AppColors.pageBg,
                        ],
                        stops: const [0.0, 0.4],
                      ),
                    ),
                  ),
                ),
              ),

              // Bottom Action Bar
              Positioned(
                bottom: MediaQuery.of(context).padding.bottom + 20,
                left: 20,
                right: 20,
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 320),
                    child: Semantics(
                      button: true,
                      label: l10n.startTest,
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          onTap: _canStart ? _startTest : null,
                          borderRadius: BorderRadius.circular(30),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            height: 56,
                            decoration: BoxDecoration(
                              color:
                                  _canStart ? AppColors.ink1 : AppColors.border,
                              borderRadius: BorderRadius.circular(30),
                              boxShadow: _canStart
                                  ? [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.3),
                                        blurRadius: 32,
                                        offset: const Offset(0, 16),
                                      )
                                    ]
                                  : [],
                            ),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Flexible(
                                  child: Padding(
                                  padding: const EdgeInsets.only(left: 16),
                                  child: Text(
                                    _prepProgress != null
                                        ? '${l10n.downloading} $_prepProgress'
                                        : l10n.startTest,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                  ),
                                ),
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _canStart
                                        ? AppColors.brand
                                        : Colors.grey.shade400,
                                    shape: BoxShape.circle,
                                  ),
                                  child: (_launching || _preparing)
                                      ? const Padding(
                                          padding: EdgeInsets.all(12),
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white),
                                        )
                                      : const Icon(Icons.arrow_forward_rounded,
                                          size: 16, color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class _DoubleBezel extends StatelessWidget {
  final Widget child;
  const _DoubleBezel({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.black.withValues(alpha: 0.03)),
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.02),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.black.withValues(alpha: 0.04)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: child,
      ),
    );
  }
}


class _StudentCard extends StatefulWidget {
  final String name;
  final String avatarLetter;
  final bool isSelected;
  final bool isDone;
  final StudentPrefetchStatus? testStatus;
  final VoidCallback? onRetryStatus;
  final VoidCallback onTap;

  const _StudentCard({
    required this.name,
    required this.avatarLetter,
    required this.isSelected,
    this.isDone = false,
    this.testStatus,
    this.onRetryStatus,
    required this.onTap,
  });

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  bool _isHovered = false;

  void _showContextMenu(Offset position) {
    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(position.dx, position.dy, position.dx, position.dy),
      items: [
        PopupMenuItem(
          value: 'copy',
          child: Row(
            children: [
              const Icon(Icons.copy, size: 18, color: AppColors.ink2),
              const SizedBox(width: 8),
              Text(AppLocalizations.of(context)!.copyName),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'copy') {
        Clipboard.setData(ClipboardData(text: widget.name));
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.nameCopied(widget.name)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.name,
      child: MouseRegion(
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: widget.onTap,
            onSecondaryTapDown: (details) => _showContextMenu(details.globalPosition),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? AppColors.brand.withValues(alpha: 0.05)
                    : _isHovered 
                        ? const Color(0xFFF0F0F0) 
                        : AppColors.pageBg,
                border: Border.all(
                  color: widget.isSelected
                      ? AppColors.brand.withValues(alpha: 0.4)
                      : _isHovered ? AppColors.border.withValues(alpha: 0.8) : AppColors.border,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: widget.isSelected ? AppColors.brand : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isSelected ? AppColors.brand : AppColors.border,
                      ),
                      boxShadow: widget.isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.brand.withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              )
                            ]
                          : [],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.avatarLetter,
                      style: TextStyle(
                        color: widget.isSelected ? Colors.white : AppColors.ink2,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.name,
                      style: TextStyle(
                        color: widget.isSelected ? AppColors.brand : AppColors.ink1,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.isDone)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Tooltip(
                        message: AppLocalizations.of(context)!.rosterDoneBadge,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.brand.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.check_circle_rounded,
                                size: 12, color: AppColors.brand),
                            const SizedBox(width: 4),
                            Text(AppLocalizations.of(context)!.rosterDoneBadge,
                                style: const TextStyle(
                                    color: AppColors.brand,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600)),
                          ]),
                        ),
                      ),
                    ),
                  if (widget.testStatus != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: StudentStatusBadge(
                        status: widget.testStatus!,
                        onRetryTap: widget.onRetryStatus,
                        tooltip: switch (widget.testStatus!) {
                          StudentPrefetchStatus.ready =>
                            AppLocalizations.of(context)!.downloaded,
                          StudentPrefetchStatus.loading =>
                            AppLocalizations.of(context)!.downloading,
                          StudentPrefetchStatus.error =>
                            AppLocalizations.of(context)!.rosterTestNotLoaded,
                        },
                      ),
                    ),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: widget.isSelected ? AppColors.brand : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isSelected ? AppColors.brand : Colors.grey.shade300,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: widget.isSelected
                        ? const Icon(Icons.check_rounded,
                            color: Colors.white, size: 10)
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SearchStudentsIntent extends Intent {
  const SearchStudentsIntent();
}
