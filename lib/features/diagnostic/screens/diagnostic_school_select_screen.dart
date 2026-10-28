// lib/features/diagnostic/screens/diagnostic_school_select_screen.dart
//
// Diagnostic kiosk flow — step 1: pick the school. Visual pattern copied
// (never imported) from lib/features/session/group_select_screen.dart's
// step-indicator/pill-grid layout; the PIN check copies
// session_setup_screen.dart's `_expectedPin`/`_confirm` logic verbatim
// (client-side-only UX deterrent, no network call for the check itself).
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart' show ApiException;
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_kiosk_api.dart';
import '../data/diagnostic_school_list.dart';
import '../widgets/diagnostic_widgets.dart';
import '../widgets/school_picker_body.dart';

/// SharedPreferences key of the last school the proctor picked.
const kLastDiagSchoolKey = 'last_diag_school_id';

class DiagnosticSchoolSelectScreen extends StatefulWidget {
  /// Test seam; defaults to the live kiosk API.
  final Future<(List<Map<String, dynamic>>, bool)> Function()? loadSchools;
  const DiagnosticSchoolSelectScreen({super.key, this.loadSchools});

  @override
  State<DiagnosticSchoolSelectScreen> createState() =>
      _DiagnosticSchoolSelectScreenState();
}

class _DiagnosticSchoolSelectScreenState
    extends State<DiagnosticSchoolSelectScreen> {
  bool _loading = true;
  String? _error;
  List<DiagnosticSchool> _schools = [];
  bool _fromCache = false;
  String _lastId = '';

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
      final (schools, fromCache) =
          await (widget.loadSchools ?? diagnosticKioskApi.listSchools)();
      var lastId = '';
      try {
        lastId = (await SharedPreferences.getInstance()).getString(
              kLastDiagSchoolKey,
            ) ??
            '';
      } catch (_) {
        // Pin is a convenience only.
      }
      if (!mounted) return;
      setState(() {
        _lastId = lastId;
        _schools = sortSchools(schools.map(DiagnosticSchool.fromMap));
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

  Future<void> _selectSchool(Map<String, dynamic> school) async {
    final schoolId = (school['school_id'] ?? '').toString();
    final schoolName = (school['school_name'] ?? '').toString();
    final schoolCode = (school['school_number'] ?? '').toString();
    final pin = (school['kiosk_pin'] ?? '').toString().trim();
    if (schoolId.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(kLastDiagSchoolKey, schoolId);
      } catch (_) {
        // Pin is a convenience only.
      }
    }
    if (!mounted) return;
    if (pin.isNotEmpty) {
      context.push(
        '/diagnostic_session_setup',
        extra: {
          'schoolId': schoolId,
          'schoolName': schoolName,
          'schoolCode': schoolCode,
          'expectedPin': pin,
        },
      );
      return;
    }
    context.push(
      '/diagnostic_class_select',
      extra: {
        'schoolId': schoolId,
        'schoolName': schoolName,
        'schoolCode': schoolCode,
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SchoolPickerFrame(
      topBarTitle: l10n.diagnosticLoginTab,
      loading: _loading,
      children: [
        Row(
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: AppColors.brand,
                shape: BoxShape.circle,
              ),
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
        if (_error == null && _fromCache) const DiagnosticOfflineBadge(),
        if (_error != null) ...[
          SchoolPickerErrorBanner(message: _error!, onRetry: _load),
          const SizedBox(height: 24),
        ] else if (_schools.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Text(
              l10n.diagnosticNoSchools,
              style: const TextStyle(fontSize: 16, color: AppColors.ink3),
            ),
          )
        else
          SchoolPickerBody(
            schools: _schools,
            lastId: _lastId,
            onSelect: (s) => _selectSchool(s.raw),
          ),
      ],
    );
  }
}
