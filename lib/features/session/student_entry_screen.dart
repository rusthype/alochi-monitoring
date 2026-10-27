import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/db/local_students_db.dart';
import '../../core/models/add_student.dart';
import '../../core/offline/lan_client_session.dart' show isOfflineModeOpen;
import '../../core/offline/offline_session.dart';
import '../../core/services/add_student_service.dart';
import '../../shared/widgets/add_student_dialog.dart';
import '../../shared/theme/app_theme.dart';
import 'runner_dispatch.dart';
import 'test_session.dart';
import '../../core/widgets/skeleton.dart';

class StudentEntryScreen extends StatefulWidget {
  final TestSession session;
  final Map<String, dynamic>? preselectedGroup;

  /// Test-only override of the "Bola qo'shish" server call; defaults to
  /// [addStudentOrQueue] (server, falling back to the local queue offline).
  final Future<AddStudentResult> Function({
    required String groupId,
    required AddStudentDraft draft,
    required bool confirmNew,
  })? addStudentOverride;

  const StudentEntryScreen({
    super.key,
    required this.session,
    this.preselectedGroup,
    this.addStudentOverride,
  });

  @override
  State<StudentEntryScreen> createState() => _StudentEntryScreenState();
}

class _StudentEntryScreenState extends State<StudentEntryScreen> {
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _searchQuery = '';
  int? _grade;
  String? _err;
  bool _launching = false;
  // "done/total" while launchRunner downloads question images; null otherwise.
  String? _imageProgress;
  List<Map<String, dynamic>> _groups = [];
  Map<String, dynamic>? _selectedGroup;
  bool _loadingGroups = true;
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _selectedStudent;
  bool _loadingStudents = false;
  // Pack mode only: roster ids that already finished this test.
  Set<String> _done = {};

  bool get _rosterActive =>
      _selectedGroup != null && (_loadingStudents || _students.isNotEmpty);

  bool get _canStart {
    if (_launching) return false;
    // A roster student (incl. a just-added pending child) is required: the
    // old anonymous manual first/last-name path (studentId == '') is replaced
    // by "Bola qo'shish", which gives the child a real/pending id.
    return _selectedStudent != null;
  }

  @override
  void initState() {
    super.initState();
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
    setState(() {
      _loadingStudents = true;
      _students = [];
      _selectedStudent = null;
      _err = null;
    });
    try {
      final fetched = await api.fetchStudents(groupId);
      // Children added while offline and not yet accepted by the server.
      final s = await _withLocalStudents(groupId, fetched);
      final done = await OfflinePackSession.current
              ?.finishedStudentIds(widget.session.testKey) ??
          <String>{};
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _students = s;
        _done = done;
        _loadingStudents = false;
        _err = s.isEmpty ? l10n.noStudentsInGroup : null;
      });
    } catch (e) {
      if (!mounted) return;
      final l10n = AppLocalizations.of(context)!;
      setState(() {
        _loadingStudents = false;
        _err = l10n.loadStudentsError;
      });
    }
  }

  Future<List<Map<String, dynamic>>> _withLocalStudents(
      String groupId, List<Map<String, dynamic>> fetched) async {
    // Pack mode: OfflinePackageApi.fetchStudents already merged the local
    // children; LAN rosters are fixed.
    if (isOfflineModeOpen) return fetched;
    final local = await LocalStudentsDb.unsyncedForGroupSafe(groupId);
    if (local.isEmpty) return fetched;
    final known = fetched.map((e) => (e['id'] ?? '').toString()).toSet();
    return [
      ...fetched,
      for (final l in local)
        if (!known.contains(l.tempId)) l.toRosterRow(),
    ];
  }

  /// Dialog result -> roster state: a created child is appended and selected;
  /// an existing candidate ("Bu shumi?" -> yes) is selected without any new
  /// record (added to the visible list when they belong to another class).
  Future<void> _addStudent() async {
    final group = _selectedGroup;
    final groupId = (group?['id'] ?? '').toString();
    if (groupId.isEmpty) return;
    final submit = widget.addStudentOverride ?? _defaultAddStudent;
    final outcome = await showAddStudentDialog(
      context,
      onSubmit: (draft, {required confirmNew}) => submit(
          groupId: groupId, draft: draft, confirmNew: confirmNew),
    );
    if (outcome == null || !mounted) return;
    final l10n = AppLocalizations.of(context)!;
    switch (outcome) {
      case AddStudentCreated(:final result):
        final row = result.toRosterRow();
        setState(() {
          _students = [..._students, row];
          _searchCtrl.clear();
          _searchQuery = '';
          _selectedStudent = row;
          _err = null;
        });
        if (result.queuedLocally) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.addStudentQueuedNotice),
            duration: const Duration(seconds: 5),
          ));
        }
      case AddStudentUseExisting(:final student):
        final idx = _students.indexWhere(
            (e) => (e['id'] ?? '').toString() == student.id);
        // Pack mode: a match in another class cannot be tested here (the
        // result's group must be the child's own pack group) - say where.
        if (idx < 0 && OfflinePackSession.isActive) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(l10n.addStudentCandidateOtherClass(
                student.name,
                student.groupName.isNotEmpty
                    ? student.groupName
                    : l10n.gradeClass(student.grade))),
            duration: const Duration(seconds: 6),
          ));
          return;
        }
        final row = idx >= 0
            ? _students[idx]
            : <String, dynamic>{
                'id': student.id,
                'name': student.name,
                'grade': student.grade,
              };
        setState(() {
          if (idx < 0) _students = [..._students, row];
          _searchCtrl.clear();
          _searchQuery = '';
          _selectedStudent = row;
          _err = null;
        });
    }
  }

  Future<AddStudentResult> _defaultAddStudent({
    required String groupId,
    required AddStudentDraft draft,
    required bool confirmNew,
  }) =>
      addStudentOrQueue(
        groupId: groupId,
        draft: draft,
        confirmNew: confirmNew,
        grade: widget.session.testGrade,
        language: (_selectedGroup?['language'] ?? '').toString(),
      );

  @override
  void dispose() {
    _searchCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
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
      // Unreachable via the UI (_canStart needs a selected student); kept as
      // a guard so a launch can never go out anonymous (studentId == '').
      setState(() => _err = l10n.enterNameError);
      return;
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
    await launchRunner(
      context,
      session: widget.session,
      firstName: firstName,
      lastName: lastName,
      studentGrade: grade,
      groupName: groupName,
      groupId: groupId,
      studentId: studentId,
      onImageProgress: (done, total) {
        if (mounted) setState(() => _imageProgress = '$done/$total');
      },
    );
    if (!mounted) return;
    setState(() => _imageProgress = null);

    // Foydalanuvchi "Keyingi o'quvchi"ni bossa yoki testdan qaytsa, 
    // to'g'ridan-to'g'ri Guruh tanlash oynasiga (GroupSelectScreen) qaytarib yuboramiz.
    Navigator.of(context).pop();
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
                                  // A LAN client's roster is fixed (the hub only
                                  // accepts its signed roster); a USB pack can
                                  // take a local child.
                                  if (!_loadingStudents &&
                                      (!isOfflineModeOpen ||
                                          OfflinePackSession.isActive))
                                    Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 12),
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: OutlinedButton.icon(
                                          key: const Key('addStudentButton'),
                                          style: OutlinedButton.styleFrom(
                                              minimumSize: const Size(0, 48)),
                                          onPressed:
                                              _launching ? null : _addStudent,
                                          icon: const Icon(
                                              Icons.person_add_alt_1_rounded,
                                              size: 18),
                                          label: Text(l10n.addStudentButton),
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
                            // Pending/done cards carry a badge under a
                            // 2-line name, so they need a taller cell.
                            final bool hasBadges = filteredStudents.any((s) =>
                                s['pending'] == true ||
                                _done.contains((s['student_code'] ??
                                        s['id'] ??
                                        '')
                                    .toString()));
                            final double itemHeight =
                                (hasBadges ? 88 : 56) *
                                    textScale.clamp(1.0, 1.6);
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
                                        isPending: student['pending'] == true,
                                        isDone: _done.contains(
                                            (student['student_code'] ??
                                                    student['id'] ??
                                                    '')
                                                .toString()),
                                        onTap: () => setState(
                                            () => _selectedStudent = student),
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
                                Padding(
                                  padding: const EdgeInsets.only(left: 16),
                                  child: Text(
                                    _launching && _imageProgress != null
                                        ? '${l10n.downloading} $_imageProgress'
                                        : l10n.startTest,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
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
                                  child: _launching
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

  /// Added by a proctor, awaiting admin approval ("Tasdiq kutilmoqda").
  final bool isPending;
  final VoidCallback onTap;

  const _StudentCard({
    required this.name,
    required this.avatarLetter,
    required this.isSelected,
    this.isDone = false,
    this.isPending = false,
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
            onSecondaryTapDown: (details) =>
                _showContextMenu(details.globalPosition),
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
                      : _isHovered
                      ? AppColors.border.withValues(alpha: 0.8)
                      : AppColors.border,
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
                        color: widget.isSelected
                            ? AppColors.brand
                            : AppColors.border,
                      ),
                      boxShadow: widget.isSelected
                          ? [
                              BoxShadow(
                                color: AppColors.brand.withValues(alpha: 0.4),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : [],
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      widget.avatarLetter,
                      style: TextStyle(
                        color: widget.isSelected
                            ? Colors.white
                            : AppColors.ink2,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          widget.name,
                          style: TextStyle(
                            color: widget.isSelected
                                ? AppColors.brand
                                : AppColors.ink1,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.isPending || widget.isDone) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 4,
                            children: [
                              if (widget.isPending)
                                Tooltip(
                                  message: AppLocalizations.of(
                                    context,
                                  )!.studentPendingBadge,
                                  child: Container(
                                    key: const Key('pendingBadge'),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.secondaryMuted,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.hourglass_top_rounded,
                                          size: 12,
                                          color: AppColors.secondary,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            AppLocalizations.of(
                                              context,
                                            )!.studentPendingBadge,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.secondary,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              if (widget.isDone)
                                Tooltip(
                                  message: AppLocalizations.of(
                                    context,
                                  )!.rosterDoneBadge,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.brand.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.check_circle_rounded,
                                          size: 12,
                                          color: AppColors.brand,
                                        ),
                                        const SizedBox(width: 4),
                                        Flexible(
                                          child: Text(
                                            AppLocalizations.of(
                                              context,
                                            )!.rosterDoneBadge,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: AppColors.brand,
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: widget.isSelected ? AppColors.brand : Colors.white,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: widget.isSelected
                            ? AppColors.brand
                            : Colors.grey.shade300,
                      ),
                    ),
                    alignment: Alignment.center,
                    child: widget.isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 10,
                          )
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
