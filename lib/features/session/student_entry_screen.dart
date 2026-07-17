import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../shared/theme/app_theme.dart';
import 'runner_dispatch.dart';
import 'test_session.dart';
import '../../core/widgets/skeleton.dart';

class StudentEntryScreen extends StatefulWidget {
  final TestSession session;
  final Map<String, dynamic>? preselectedGroup;

  const StudentEntryScreen({
    super.key,
    required this.session,
    this.preselectedGroup,
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
  List<Map<String, dynamic>> _groups = [];
  Map<String, dynamic>? _selectedGroup;
  bool _loadingGroups = true;
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _selectedStudent;
  bool _loadingStudents = false;

  bool get _rosterActive =>
      _selectedGroup != null && (_loadingStudents || _students.isNotEmpty);

  bool get _canStart {
    if (_launching) return false;
    if (_selectedStudent != null) return true;
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
      if (!context.mounted) return;
      setState(() {
        _groups = g;
        _loadingGroups = false;
      });
    } catch (_) {
      if (!context.mounted) return;
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
    });
    try {
      final s = await api.fetchStudents(groupId);
      if (!context.mounted) return;
      setState(() {
        _students = s;
        _loadingStudents = false;
      });
    } catch (_) {
      if (!context.mounted) return;
      setState(() {
        _loadingStudents = false;
      });
    }
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
    );
    if (!context.mounted) return;
    setState(() {
      _firstCtrl.clear();
      _lastCtrl.clear();
      _selectedStudent = null;
      _launching = false;
    });
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
          backgroundColor: const Color(0xFFFAFAFA),
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
                                    mainAxisExtent: 56,
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
                                    mainAxisExtent: 56,
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
                                        onTap: () => setState(
                                            () => _selectedStudent = student),
                                      );
                                    },
                                    childCount: filteredStudents.length,
                                  ),
                                ),
                              );
                            } else {
                              return const SliverToBoxAdapter(
                                  child: SizedBox());
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
                                width: 40,
                                height: 40,
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFAFAFA),
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
                          const SizedBox(width: 40), // Spacer for centering
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
                          const Color(0xFFFAFAFA).withValues(alpha: 0),
                          const Color(0xFFFAFAFA),
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
                                    l10n.startTest,
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
  final VoidCallback onTap;

  const _StudentCard({
    required this.name,
    required this.avatarLetter,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_StudentCard> createState() => _StudentCardState();
}

class _StudentCardState extends State<_StudentCard> {
  bool _isHovered = false;

  void _showContextMenu(BuildContext context, Offset position) {
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
        if (!context.mounted) return;
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
            onSecondaryTapDown: (details) => _showContextMenu(context, details.globalPosition),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: widget.isSelected
                    ? AppColors.brand.withValues(alpha: 0.05)
                    : _isHovered 
                        ? const Color(0xFFF0F0F0) 
                        : const Color(0xFFFAFAFA),
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
