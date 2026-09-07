// lib/features/diagnostic/screens/diagnostic_student_select_screen.dart
//
// Diagnostic kiosk flow — step 3: search + 2-col avatar-card grid + floating
// CTA, pattern copied (never imported) from
// lib/features/session/student_entry_screen.dart. Shows ALL candidates in
// the class regardless of finished status (decision #5 in the plan) — a
// repeat attempt surfaces the CAT engine's own "already finished" error.
// `parent_phone` is never requested/rendered here (the backend never sends
// it for this endpoint).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart' show ApiException;
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_kiosk_api.dart';
import '../widgets/diagnostic_widgets.dart';

class DiagnosticStudentSelectScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;
  final String classLabel;

  const DiagnosticStudentSelectScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
    required this.classLabel,
  });

  @override
  State<DiagnosticStudentSelectScreen> createState() =>
      _DiagnosticStudentSelectScreenState();
}

class _DiagnosticStudentSelectScreenState
    extends State<DiagnosticStudentSelectScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _students = [];
  Map<String, dynamic>? _selected;
  final _searchCtrl = TextEditingController();
  String _query = '';

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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final students = await diagnosticKioskApi.listStudents(
          widget.schoolId, widget.classLabel);
      if (!mounted) return;
      setState(() {
        _students = students;
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
    return _students
        .where((s) =>
            (s['student_name'] ?? '').toString().toLowerCase().contains(_query))
        .toList();
  }

  /// Grade is derived from the class label's leading digits (e.g. "4-A" → 4).
  int _gradeFromClassLabel() {
    final match = RegExp(r'^(\d+)').firstMatch(widget.classLabel);
    return int.tryParse(match?.group(1) ?? '') ?? 1;
  }

  void _start() {
    final s = _selected;
    if (s == null) return;
    context.push('/diagnostic_test_runner', extra: {
      'attemptId': (s['attempt_id'] ?? '').toString(),
      'studentName': (s['student_name'] ?? '').toString(),
      'grade': _gradeFromClassLabel(),
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final filtered = _filtered;
    return Scaffold(
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
                              const DiagnosticStepIndicator('Qadam 3'),
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
                                  prefixIcon: const Icon(Icons.search_rounded,
                                      size: 20),
                                ),
                              ),
                              const SizedBox(height: 20),
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
                                                fontWeight: FontWeight.w500)),
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
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 40),
                                  child: Text(
                                    l10n.diagnosticNoStudents,
                                    style: const TextStyle(
                                        fontSize: 16, color: AppColors.ink3),
                                  ),
                                )
                              else
                                GridView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
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
                                    return DiagnosticStudentCard(
                                      name: (student['student_name'] ?? '')
                                          .toString(),
                                      isSelected: _selected == student,
                                      onTap: () =>
                                          setState(() => _selected = student),
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
                enabled: _selected != null,
                onTap: _start,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
