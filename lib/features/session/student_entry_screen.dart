import 'package:flutter/material.dart';
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
    });
    try {
      final s = await api.fetchStudents(groupId);
      if (!mounted) return;
      setState(() {
        _students = s;
        _loadingStudents = false;
      });
    } catch (_) {
      if (!mounted) return;
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
    if (!mounted) return;
    setState(() {
      _firstCtrl.clear();
      _lastCtrl.clear();
      _selectedStudent = null;
      _launching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final showTextInputs = !_rosterActive;
    final l10n = AppLocalizations.of(context)!;
    final isSmall = MediaQuery.of(context).size.width < 800;

    return Scaffold(
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
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                  top: isSmall ? 60 : 80, bottom: 140, left: isSmall ? 16 : 20, right: isSmall ? 16 : 20),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 600),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Eyebrow tag removed per user request
                      const SizedBox(height: 12),
                      Text(
                        'Testni kim\ntopshiradi?',
                        style: TextStyle(
                          fontSize: isSmall ? 28 : 36,
                          fontWeight: FontWeight.w900,
                          height: 1.1,
                          letterSpacing: -1,
                          color: AppColors.ink1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (_rosterActive && _students.isNotEmpty)
                        Text(
                          '${_students.length} o\'quvchi ro\'yxatda mavjud',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.ink2,
                          ),
                        ),
                      const SizedBox(height: 24),

                      // Outer Shell Form / Grid
                      _OuterShell(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showTextInputs) ...[
                              _Field(
                                  label: l10n.firstName,
                                  controller: _firstCtrl,
                                  focusNode: _firstFocus,
                                  textInputAction: TextInputAction.next,
                                  onSubmitted: (_) => _lastFocus.requestFocus(),
                              ),
                              const SizedBox(height: 12),
                              _Field(
                                  label: l10n.lastName, 
                                  controller: _lastCtrl,
                                  focusNode: _lastFocus,
                                  textInputAction: TextInputAction.done,
                                  onSubmitted: (_) {
                                    if (_canStart) _startTest();
                                  },
                              ),
                              const SizedBox(height: 20),
                            ],
                            if (_loadingGroups)
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: List.generate(
                                  4,
                                  (_) => const Skeleton(width: 80, height: 40, borderRadius: 10),
                                ),
                              )
                            else if (_groups.isNotEmpty &&
                                widget.preselectedGroup == null) ...[
                              Text(l10n.selectGroup,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: _groups.map((group) {
                                  final selected = _selectedGroup == group;
                                  return Semantics(
                                    button: true,
                                    label: (group['display'] ?? group['name'] ?? '').toString(),
                                    child: GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          _selectedGroup = group;
                                          _selectedStudent = null;
                                          _students = [];
                                        });
                                        _loadStudents();
                                      },
                                      child: AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 160),
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 14, vertical: 10),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? AppColors.brand.withOpacity(0.1)
                                              : Colors.white,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: selected
                                                ? AppColors.brand
                                                : AppColors.border,
                                          ),
                                        ),
                                        child: Text(
                                          (group['display'] ??
                                                  group['name'] ??
                                                  '')
                                              .toString(),
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
                              if (_loadingStudents)
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final crossAxisCount = constraints.maxWidth > 400 ? 2 : 1;
                                    return GridView.builder(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        mainAxisSpacing: 8,
                                        crossAxisSpacing: 8,
                                        mainAxisExtent: 56,
                                      ),
                                      itemCount: 6,
                                      itemBuilder: (context, index) => const Skeleton(height: 56, borderRadius: 12),
                                    );
                                  },
                                )
                              else if (_students.isNotEmpty) ...[
                                LayoutBuilder(
                                  builder: (context, constraints) {
                                    final crossAxisCount =
                                        constraints.maxWidth > 400 ? 2 : 1;
                                    return GridView.builder(
                                      shrinkWrap: true,
                                      physics:
                                          const NeverScrollableScrollPhysics(),
                                      gridDelegate:
                                          SliverGridDelegateWithFixedCrossAxisCount(
                                        crossAxisCount: crossAxisCount,
                                        mainAxisSpacing: 8,
                                        crossAxisSpacing: 8,
                                        mainAxisExtent: 56,
                                      ),
                                      itemCount: _students.length,
                                      itemBuilder: (context, index) {
                                        final student = _students[index];
                                        final name =
                                            (student['name'] ?? '').toString();
                                        final initial = name.isNotEmpty
                                            ? name[0].toUpperCase()
                                            : '?';
                                        return _StudentCard(
                                          name: name,
                                          avatarLetter: initial,
                                          isSelected:
                                              _selectedStudent == student,
                                          onTap: () => setState(
                                              () => _selectedStudent = student),
                                        );
                                      },
                                    );
                                  },
                                )
                              ],
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
                                      padding: const EdgeInsets.only(right: 8),
                                      child: Semantics(
                                        button: true,
                                        label: '$n - sinf',
                                        child: GestureDetector(
                                          onTap: () => setState(() => _grade = n),
                                          child: AnimatedContainer(
                                            duration:
                                                const Duration(milliseconds: 160),
                                            height: 48,
                                            decoration: BoxDecoration(
                                              color: selected
                                                  ? AppColors.brand
                                                      .withOpacity(0.1)
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
                            if (_err != null) ...[
                              const SizedBox(height: 12),
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: AppColors.err.withOpacity(0.08),
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
                                            color: AppColors.err, fontSize: 13),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
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
                        label: 'Ortga',
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
                                    : widget.session.schoolLabel.toUpperCase(),
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
                      const Color(0xFFFAFAFA).withOpacity(0),
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
                  label: 'Testni boshlash',
                  child: GestureDetector(
                    onTap: _canStart ? _startTest : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 56,
                      decoration: BoxDecoration(
                        color: _canStart ? AppColors.ink1 : AppColors.border,
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: _canStart
                            ? [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.3),
                                  blurRadius: 32,
                                  offset: const Offset(0, 16),
                                )
                              ]
                            : [],
                      ),
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
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
                                        strokeWidth: 2, color: Colors.white),
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
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final FocusNode? focusNode;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const _Field({
    required this.label, 
    required this.controller,
    this.focusNode,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: AppColors.ink1)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: textInputAction,
          onSubmitted: onSubmitted,
          decoration: InputDecoration(
            hintText: label,
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.brand),
            ),
          ),
        ),
      ],
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
        color: Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.black.withOpacity(0.03)),
      ),
      padding: const EdgeInsets.all(4),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.black.withOpacity(0.04)),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: child,
      ),
    );
  }
}

class _OuterShell extends StatelessWidget {
  final Widget child;
  const _OuterShell({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.black.withOpacity(0.03)),
      ),
      padding: const EdgeInsets.all(6),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.02),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.black.withOpacity(0.04)),
        ),
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    );
  }
}

class _StudentCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: name,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? AppColors.brand.withOpacity(0.05)
                : const Color(0xFFFAFAFA),
            border: Border.all(
              color: isSelected
                  ? AppColors.brand.withOpacity(0.4)
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
                  color: isSelected ? AppColors.brand : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.brand : AppColors.border,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: AppColors.brand.withOpacity(0.4),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : [],
                ),
                alignment: Alignment.center,
                child: Text(
                  avatarLetter,
                  style: TextStyle(
                    color: isSelected ? Colors.white : AppColors.ink2,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: TextStyle(
                    color: isSelected ? AppColors.brand : AppColors.ink1,
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
                  color: isSelected ? AppColors.brand : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected ? AppColors.brand : Colors.grey.shade300,
                  ),
                ),
                alignment: Alignment.center,
                child: isSelected
                    ? const Icon(Icons.check_rounded,
                        color: Colors.white, size: 10)
                    : const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }
}
