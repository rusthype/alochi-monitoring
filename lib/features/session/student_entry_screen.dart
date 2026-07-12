import 'package:flutter/material.dart';
import '../../core/api/api_client.dart';
import '../../shared/theme/app_theme.dart';
import 'runner_dispatch.dart';
import 'test_session.dart';

class StudentEntryScreen extends StatefulWidget {
  final TestSession session;

  /// Set by GroupSelectScreen when the user already picked their group
  /// (the new maktab→guruh→test→o'quvchi flow) — the group list/loader
  /// below is skipped entirely and the roster loads straight away.
  /// Null for the legacy/guruhsiz-maktab path, which still loads groups
  /// itself (unchanged behavior).
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
  int? _grade;
  String? _err;
  bool _launching = false;
  List<Map<String, dynamic>> _groups = [];
  Map<String, dynamic>? _selectedGroup;
  bool _loadingGroups = true;
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _selectedStudent;
  bool _loadingStudents = false;

  /// True when a group is selected and the roster is either loading or has entries.
  /// When true the Ism/Familiya text inputs are hidden and the roster is shown instead.
  bool get _rosterActive =>
      _selectedGroup != null && (_loadingStudents || _students.isNotEmpty);

  bool get _canStart {
    if (_launching) return false;
    if (_selectedStudent != null) return true;
    // Roster is loading or has students but none tapped yet
    if (_selectedGroup != null && (_loadingStudents || _students.isNotEmpty)) {
      return false;
    }
    // No roster — require a typed name
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
      // Guruh avvalgi qadamda (GroupSelectScreen) allaqachon tanlangan —
      // qayta guruh ro'yxatini yuklamaymiz, to'g'ridan roster'ga o'tamiz.
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
    super.dispose();
  }

  Future<void> _startTest() async {
    String firstName;
    String lastName;
    String studentId;

    if (_selectedStudent != null) {
      firstName = (_selectedStudent!['first_name'] ?? '').toString();
      lastName = (_selectedStudent!['last_name'] ?? '').toString();
      if (firstName.isEmpty && lastName.isEmpty) {
        // Fallback: split the composite name field (last first, Uzbek convention)
        final parts = (_selectedStudent!['name'] ?? '').toString().split(' ');
        lastName = parts.isNotEmpty ? parts.first : '';
        firstName = parts.length > 1 ? parts.sublist(1).join(' ') : '';
      }
      studentId = (_selectedStudent!['student_code'] ?? _selectedStudent!['id'] ?? '').toString();
    } else {
      final first = _firstCtrl.text.trim();
      final last = _lastCtrl.text.trim();
      if (first.isEmpty || last.isEmpty) {
        setState(() => _err = 'Ism va familiyani kiriting');
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
        setState(() => _err = 'Guruhni tanlang');
        return;
      }
      grade = widget.session.testGrade;
      groupName = (_selectedGroup!['name'] ?? '').toString();
      groupId = (_selectedGroup!['id'] ?? '').toString();
    } else {
      if (_grade == null) {
        setState(() => _err = 'Sinfni tanlang');
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
      _grade = null;
      _selectedGroup = null;
      _students = [];
      _selectedStudent = null;
      _launching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Text inputs are shown when no roster is active (no group selected, or
    // group selected but roster came back empty).
    final showTextInputs = !_rosterActive;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        elevation: 0,
        title: Text(widget.session.title, style: AppTextStyles.titleMedium),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // School chip
                Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.secondaryMuted,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.school_rounded,
                            size: 14, color: AppColors.secondary),
                        const SizedBox(width: 6),
                        Text(
                          widget.session.schoolLabel.isEmpty
                              ? 'Umumiy testlar'
                              : widget.session.schoolLabel,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.secondary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Ism/Familiya — hidden when a roster is active
                if (showTextInputs) ...[
                  _Field(label: 'Ism', controller: _firstCtrl),
                  const SizedBox(height: 12),
                  _Field(label: 'Familiya', controller: _lastCtrl),
                  const SizedBox(height: 20),
                ],
                // Group / grade selector
                if (_loadingGroups)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(strokeWidth: 2),
                          SizedBox(height: 8),
                          Text(
                            'Guruhlar yuklanmoqda...',
                            style: TextStyle(fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  )
                else if (_groups.isNotEmpty) ...[
                  // Guruh tanlash chiplari faqat guruh HALI tanlanmagan
                  // bo'lsa ko'rsatiladi — GroupSelectScreen'dan kelganda
                  // (preselectedGroup != null) guruh allaqachon fiksirlangan,
                  // qayta tanlashning hojati yo'q.
                  if (widget.preselectedGroup == null) ...[
                    const Text('Guruhni tanlang',
                        style: AppTextStyles.labelLarge),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: _groups.map((group) {
                        final selected = _selectedGroup == group;
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _selectedGroup = group;
                              _selectedStudent = null;
                              _students = [];
                            });
                            _loadStudents();
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 160),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppColors.secondary
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppColors.secondary
                                    : AppColors.border,
                              ),
                            ),
                            child: Text(
                              (group['display'] ?? group['name'] ?? '')
                                  .toString(),
                              style: AppTextStyles.labelLarge.copyWith(
                                color:
                                    selected ? Colors.white : AppColors.ink1,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ] else ...[
                    // Guruh allaqachon tanlangan (oldingi qadamda) — nom
                    // sifatida ko'rsatamiz, chip qayta tanlash uchun emas.
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: AppColors.secondaryMuted,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.groups_rounded,
                              size: 16, color: AppColors.secondary),
                          const SizedBox(width: 8),
                          Text(
                            (widget.preselectedGroup!['display'] ??
                                    widget.preselectedGroup!['name'] ??
                                    '')
                                .toString(),
                            style: AppTextStyles.labelLarge.copyWith(
                              color: AppColors.secondary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  // ── Student roster section (shown only when a group is selected) ──
                  if (_selectedGroup != null) ...[
                    const SizedBox(height: 20),
                    if (_loadingStudents)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.secondary,
                          ),
                        ),
                      )
                    else if (_students.isNotEmpty) ...[
                      const Text("O'quvchini tanlang",
                          style: AppTextStyles.labelLarge),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: _students.map((student) {
                          final selected = _selectedStudent == student;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _selectedStudent = student),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.secondary
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.secondary
                                      : AppColors.border,
                                ),
                              ),
                              child: Text(
                                (student['name'] ?? '').toString(),
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: selected
                                      ? Colors.white
                                      : AppColors.ink1,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                    // When _students is empty after load, _rosterActive = false
                    // so showTextInputs = true and Ism/Familiya are visible at top.
                  ],
                ] else ...[
                  const Text('Sinfni tanlang', style: AppTextStyles.labelLarge),
                  const SizedBox(height: 10),
                  Row(
                    children: [1, 2, 3, 4].map((n) {
                      final selected = _grade == n;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: GestureDetector(
                            onTap: () => setState(() => _grade = n),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 160),
                              height: 48,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.secondary
                                    : AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: selected
                                      ? AppColors.secondary
                                      : AppColors.border,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$n',
                                style: AppTextStyles.labelLarge.copyWith(
                                  color: selected
                                      ? Colors.white
                                      : AppColors.ink1,
                                  fontWeight: FontWeight.w700,
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
                      color: AppColors.err.withValues(alpha: .08),
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
                const SizedBox(height: 24),
                SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _canStart ? _startTest : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.secondary,
                      foregroundColor: Colors.white,
                    ),
                    icon: _launching
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.play_arrow_rounded),
                    label: Text(
                        _launching ? 'Yuklanmoqda...' : 'Testni boshlash'),
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

class _Field extends StatelessWidget {
  final String label;
  final TextEditingController controller;

  const _Field({required this.label, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.labelLarge),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          decoration: InputDecoration(hintText: label),
        ),
      ],
    );
  }
}
