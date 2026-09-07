// lib/features/diagnostic/screens/diagnostic_class_select_screen.dart
//
// Diagnostic kiosk flow — step 2: pick the class within the chosen school.
// Same step-indicator/pill-grid pattern as diagnostic_school_select_screen.
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart' show ApiException;
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_kiosk_api.dart';
import '../widgets/diagnostic_widgets.dart';

class DiagnosticClassSelectScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;

  const DiagnosticClassSelectScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
  });

  @override
  State<DiagnosticClassSelectScreen> createState() =>
      _DiagnosticClassSelectScreenState();
}

class _DiagnosticClassSelectScreenState
    extends State<DiagnosticClassSelectScreen> {
  bool _loading = true;
  String? _error;
  List<String> _classes = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final classes = await diagnosticKioskApi.listClasses(widget.schoolId);
      if (!mounted) return;
      setState(() {
        _classes = classes;
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

  void _selectClass(String classLabel) {
    context.push('/diagnostic_student_select', extra: {
      'schoolId': widget.schoolId,
      'schoolName': widget.schoolName,
      'classLabel': classLabel,
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
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
                          top: 90, bottom: 40, left: 16, right: 16),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 768),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const DiagnosticStepIndicator('Qadam 2'),
                              const SizedBox(height: 12),
                              Text(
                                l10n.diagnosticSelectClass,
                                style: const TextStyle(
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.5,
                                  color: AppColors.ink1,
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (_error != null) ...[
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
                                ),
                              ] else if (_classes.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 40),
                                  child: Text(
                                    l10n.diagnosticNoClasses,
                                    style: const TextStyle(
                                        fontSize: 16, color: AppColors.ink3),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: _classes
                                      .map((c) => DiagnosticPillButton(
                                            label: c,
                                            isSelected: false,
                                            onTap: () => _selectClass(c),
                                          ))
                                      .toList(),
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
                  child: DiagnosticTopBar(title: widget.schoolName),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
