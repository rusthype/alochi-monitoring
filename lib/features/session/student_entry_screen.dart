import 'package:flutter/material.dart';
import '../../shared/theme/app_theme.dart';
import 'runner_dispatch.dart';
import 'test_session.dart';

class StudentEntryScreen extends StatefulWidget {
  final TestSession session;
  const StudentEntryScreen({super.key, required this.session});

  @override
  State<StudentEntryScreen> createState() => _StudentEntryScreenState();
}

class _StudentEntryScreenState extends State<StudentEntryScreen> {
  final _firstCtrl = TextEditingController();
  final _lastCtrl = TextEditingController();
  int? _grade;
  String? _err;
  bool _launching = false;

  @override
  void dispose() {
    _firstCtrl.dispose();
    _lastCtrl.dispose();
    super.dispose();
  }

  Future<void> _startTest() async {
    final first = _firstCtrl.text.trim();
    final last = _lastCtrl.text.trim();
    if (first.isEmpty || last.isEmpty) {
      setState(() => _err = 'Ism va familiyani kiriting');
      return;
    }
    if (_grade == null) {
      setState(() => _err = 'Sinfni tanlang');
      return;
    }
    setState(() {
      _err = null;
      _launching = true;
    });
    await launchRunner(
      context,
      session: widget.session,
      firstName: first,
      lastName: last,
      studentGrade: _grade!,
    );
    if (!mounted) return;
    setState(() {
      _firstCtrl.clear();
      _lastCtrl.clear();
      _grade = null;
      _launching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
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
                      color: AppColors.primaryMuted,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.school_rounded,
                            size: 14, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          widget.session.schoolLabel.isEmpty
                              ? 'Umumiy testlar'
                              : widget.session.schoolLabel,
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // First name
                _Field(label: 'Ism', controller: _firstCtrl),
                const SizedBox(height: 12),
                // Last name
                _Field(label: 'Familiya', controller: _lastCtrl),
                const SizedBox(height: 20),
                // Grade grid
                Text('Sinfni tanlang', style: AppTextStyles.labelLarge),
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
                                  ? AppColors.primary
                                  : AppColors.surface,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: selected
                                    ? AppColors.primary
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
                    onPressed: _launching ? null : _startTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
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
                    label: Text(_launching ? 'Yuklanmoqda...' : 'Testni boshlash'),
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
