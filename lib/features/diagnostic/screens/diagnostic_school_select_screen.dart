// lib/features/diagnostic/screens/diagnostic_school_select_screen.dart
//
// Diagnostic kiosk flow — step 1: pick the school. Visual pattern copied
// (never imported) from lib/features/session/group_select_screen.dart's
// step-indicator/pill-grid layout; the PIN check copies
// session_setup_screen.dart's `_expectedPin`/`_confirm` logic verbatim
// (client-side-only UX deterrent, no network call for the check itself).
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart' show ApiException;
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_kiosk_api.dart';
import '../widgets/diagnostic_widgets.dart';

class DiagnosticSchoolSelectScreen extends StatefulWidget {
  const DiagnosticSchoolSelectScreen({super.key});

  @override
  State<DiagnosticSchoolSelectScreen> createState() =>
      _DiagnosticSchoolSelectScreenState();
}

class _DiagnosticSchoolSelectScreenState
    extends State<DiagnosticSchoolSelectScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _schools = [];

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
      final schools = await diagnosticKioskApi.listSchools();
      if (!mounted) return;
      setState(() {
        _schools = schools;
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

  Future<void> _selectSchool(Map<String, dynamic> school) async {
    final schoolId = (school['school_id'] ?? '').toString();
    final schoolName = (school['school_name'] ?? '').toString();
    final schoolCode = (school['school_number'] ?? '').toString();
    final pin = (school['kiosk_pin'] ?? '').toString().trim();
    if (!mounted) return;
    if (pin.isNotEmpty) {
      context.push('/diagnostic_session_setup', extra: {
        'schoolId': schoolId,
        'schoolName': schoolName,
        'schoolCode': schoolCode,
        'expectedPin': pin,
      });
      return;
    }
    context.push('/diagnostic_class_select', extra: {
      'schoolId': schoolId,
      'schoolName': schoolName,
      'schoolCode': schoolCode,
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
                              Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                        color: AppColors.brand,
                                        shape: BoxShape.circle),
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    l10n.diagnosticBadge,
                                    style: const TextStyle(
                                      color: AppColors.brand,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      letterSpacing: 1,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              DiagnosticStepIndicator(l10n.diagnosticStep(1)),
                              const SizedBox(height: 12),
                              Text(
                                l10n.diagnosticSelectSchoolPrompt,
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
                                const SizedBox(height: 24),
                              ] else if (_schools.isEmpty)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 40),
                                  child: Text(
                                    l10n.diagnosticNoSchools,
                                    style: const TextStyle(
                                        fontSize: 16, color: AppColors.ink3),
                                  ),
                                )
                              else
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  children: _schools
                                      .map((s) => DiagnosticPillButton(
                                            label: (s['school_name'] ?? '')
                                                .toString(),
                                            isSelected: false,
                                            onTap: () => _selectSchool(s),
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
                  child: DiagnosticTopBar(title: l10n.diagnosticLoginTab),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
