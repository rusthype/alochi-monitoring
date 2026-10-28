// lib/features/auth/school_pick_screen.dart
//
// Full-screen monitoring school picker opened from the login "Школы" pill
// (replaces the old catalog bottom sheet). Same UI as the diagnostic picker
// ([SchoolPickerBody]); a tap hands the school to /session_setup, which asks
// for the PIN and continues to /group_select/<code>.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../core/api/api_client.dart';
import '../../core/services/test_catalog_service.dart';
import '../../shared/theme/app_theme.dart';
import '../diagnostic/data/diagnostic_school_list.dart';
import '../diagnostic/widgets/school_picker_body.dart';
import '../session/session_providers.dart';
import 'monitoring_school_list.dart';

/// SharedPreferences key of the last monitoring school the proctor picked
/// (separate from the diagnostic picker's `last_diag_school_id`).
const kLastMonitoringSchoolKey = 'last_monitoring_school_id';

typedef MonitoringSchoolSources = ({
  List<CatalogEntry> entries,
  List<Map<String, String>> schools,
});

Future<MonitoringSchoolSources> _loadLive() async {
  final results = await Future.wait([
    testCatalogService.refresh(),
    api.fetchCatalogSchools(),
  ]);
  return (
    entries: results[0] as List<CatalogEntry>,
    schools: results[1] as List<Map<String, String>>,
  );
}

class SchoolPickScreen extends StatefulWidget {
  /// Test seam; defaults to the live catalog + schools endpoints.
  final Future<MonitoringSchoolSources> Function()? load;
  const SchoolPickScreen({super.key, this.load});

  @override
  State<SchoolPickScreen> createState() => _SchoolPickScreenState();
}

class _SchoolPickScreenState extends State<SchoolPickScreen> {
  bool _loading = true;
  String? _error;
  List<DiagnosticSchool> _schools = [];
  String _lastId = '';

  @override
  void initState() {
    super.initState();
    // Needs l10n (fallback labels), which is only available after initState.
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final src = await (widget.load ?? _loadLive)();
      var lastId = '';
      try {
        lastId = (await SharedPreferences.getInstance()).getString(
              kLastMonitoringSchoolKey,
            ) ??
            '';
      } catch (_) {
        // Pin is a convenience only.
      }
      final rows = mergeMonitoringSchools(
        src.entries,
        src.schools,
        fallbackLabel: l10n.schoolPrefix,
      );
      if (!mounted) return;
      setState(() {
        _lastId = lastId;
        _schools = sortSchools(
          rows.map(
            (r) => DiagnosticSchool.fromMap({
              // id doubles as the pin identity: old catalog rows have no UUID.
              'school_id': r.id.isNotEmpty ? r.id : r.code,
              'school_name': r.label,
              'school_number': r.code,
              'row': r,
            }),
          ),
        );
        _loading = false;
      });
    } catch (e) {
      debugPrint('SchoolPickScreen load error: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e is ApiException ? e.message : e.toString();
      });
    }
  }

  Future<void> _remember(String id) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kLastMonitoringSchoolKey, id);
    } catch (_) {
      // Pin is a convenience only.
    }
  }

  void _select(DiagnosticSchool s) {
    final row = s.raw['row'] as MonitoringSchoolRow;
    final entry = row.entry ??
        CatalogEntry(
          testKey: '',
          title: row.label,
          grade: 0,
          version: 0,
          status: CatalogStatus.notDownloaded,
          schoolButtons: [
            SchoolButton(
              pin: '',
              label: row.label,
              schoolCode: row.code,
              schoolId: row.id,
              randomVariant: false,
            ),
          ],
        );
    final container = ProviderScope.containerOf(context);
    container.read(selectedCatalogEntryProvider.notifier).state = entry;
    container.read(selectedSchoolCodeProvider.notifier).state = row.code;
    _remember(s.id);
    // push (not replace): this screen stays underneath as the back target.
    context.push('/session_setup', extra: {'testKey': entry.testKey});
  }

  void _close() => context.canPop() ? context.pop() : context.go('/');

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
      // Esc reaches CallbackShortcuts from a focused search field too (the
      // field is a descendant); autofocus covers the nothing-focused case.
      child: Focus(
        autofocus: true,
        child: SchoolPickerFrame(
          topBarTitle: l10n.schools,
          loading: _loading,
          children: [
            Text(
              l10n.selectSchool,
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.5,
                color: AppColors.ink1,
              ),
            ),
            const SizedBox(height: 24),
            if (_error != null)
              SchoolPickerErrorBanner(message: _error!, onRetry: _load)
            else if (_schools.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Text(
                  l10n.testsNotFound,
                  style: const TextStyle(fontSize: 16, color: AppColors.ink3),
                ),
              )
            else
              SchoolPickerBody(
                schools: _schools,
                lastId: _lastId,
                onSelect: _select,
              ),
          ],
        ),
      ),
    );
  }
}
