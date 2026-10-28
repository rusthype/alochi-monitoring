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
import '../../core/api/api_error_text.dart';
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
  // Each source may fail on its own; the screen only fails when NOTHING could
  // be loaded (an empty list must mean "no schools", not "no network").
  Future<Object> settle<T>(Future<T> f) =>
      f.then<Object>((v) => v as Object, onError: (Object e) => _Failed(e));
  final results = await Future.wait([
    settle(testCatalogService.refresh()),
    settle(api.fetchCatalogSchools(strict: true)),
  ]);
  final entries =
      results[0] is _Failed ? <CatalogEntry>[] : results[0] as List<CatalogEntry>;
  final schools = results[1] is _Failed
      ? <Map<String, String>>[]
      : results[1] as List<Map<String, String>>;
  final anySchool =
      schools.isNotEmpty || entries.any((e) => e.schoolButtons.isNotEmpty);
  if (!anySchool) {
    final failure = results.whereType<_Failed>().firstOrNull;
    if (failure != null) throw failure.error;
  }
  return (entries: entries, schools: schools);
}

class _Failed {
  final Object error;
  const _Failed(this.error);
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

  /// A school card was tapped and its setup screen is still up: further taps
  /// are ignored (a double-tap would stack two /session_setup routes).
  bool _selecting = false;

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
        _error = localizedApiError(l10n, e);
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

  Future<void> _select(DiagnosticSchool s) async {
    if (_selecting) return;
    _selecting = true;
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
    try {
      await context.push('/session_setup', extra: {'testKey': entry.testKey});
    } finally {
      _selecting = false;
    }
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
