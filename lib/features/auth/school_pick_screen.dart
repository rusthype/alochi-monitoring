// lib/features/auth/school_pick_screen.dart
//
// Full-screen monitoring school picker opened from the login "Школы" pill
// (replaces the old catalog bottom sheet). Same UI as the diagnostic picker
// ([SchoolPickerBody]); a tap hands the school to /session_setup, which asks
// for the PIN and continues to /group_select/<code>.
import 'dart:convert';

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

/// SharedPreferences key of the last successfully loaded school list (JSON
/// array of `{school_code, school_id, label}`), shown only when the live load
/// fails. Fully replaced on every successful live load.
const kCachedMonitoringSchoolsKey = 'cached_monitoring_schools';

Future<MonitoringSchoolSources> _loadLive() => loadMonitoringSchoolSources(
      fetchEntries: testCatalogService.refresh,
      fetchSchools: () => api.fetchCatalogSchools(strict: true),
    );

/// Live-first load. The list always comes from the live responses when they
/// succeed (and then REPLACES the persisted copy, so a removed school cannot
/// come back). The persisted copy is used only when the live schools list
/// fails (offline / 5xx / timeout); an empty successful live list is a real
/// "no schools" and is never refilled from it.
///
/// `fetchEntries` degrades to the disk cache offline, but cached entries carry
/// no `schoolButtons`, so offline the persisted copy is the only school source.
@visibleForTesting
Future<MonitoringSchoolSources> loadMonitoringSchoolSources({
  required Future<List<CatalogEntry>> Function() fetchEntries,
  required Future<List<Map<String, String>>> Function() fetchSchools,
}) async {
  Future<Object> settle<T>(Future<T> f) =>
      f.then<Object>((v) => v as Object, onError: (Object e) => _Failed(e));
  final results = await Future.wait([
    settle(fetchEntries()),
    settle(fetchSchools()),
  ]);
  final entries = results[0] is _Failed
      ? <CatalogEntry>[]
      : results[0] as List<CatalogEntry>;
  final entriesOk = results[0] is! _Failed;
  final schoolsOk = results[1] is! _Failed;
  final schools = schoolsOk
      ? results[1] as List<Map<String, String>>
      : <Map<String, String>>[];

  // An empty list is "no schools" only when nothing failed alongside it.
  if (schoolsOk && (entriesOk || schools.isNotEmpty)) {
    await _persistSchools(entries, schools);
    return (entries: entries, schools: schools);
  }

  final saved = await _readPersistedSchools();
  if (saved.isNotEmpty || entries.any((e) => e.schoolButtons.isNotEmpty)) {
    return (entries: entries, schools: saved);
  }
  throw results.whereType<_Failed>().first.error;
}

Future<void> _persistSchools(
  List<CatalogEntry> entries,
  List<Map<String, String>> schools,
) async {
  try {
    final rows =
        mergeMonitoringSchools(entries, schools, fallbackLabel: (_) => '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      kCachedMonitoringSchoolsKey,
      jsonEncode([
        for (final r in rows)
          {'school_code': r.code, 'school_id': r.id, 'label': r.label},
      ]),
    );
  } catch (e) {
    debugPrint('SchoolPickScreen: persist schools failed: $e');
  }
}

Future<List<Map<String, String>>> _readPersistedSchools() async {
  try {
    final raw = (await SharedPreferences.getInstance())
        .getString(kCachedMonitoringSchoolsKey);
    if (raw == null || raw.isEmpty) return [];
    final data = jsonDecode(raw);
    if (data is! List) return [];
    return [
      for (final e in data.whereType<Map>())
        if ((e['school_code']?.toString() ?? '').isNotEmpty)
          {
            'school_code': e['school_code'].toString(),
            'school_id': e['school_id']?.toString() ?? '',
            'label': e['label']?.toString() ?? '',
          },
    ];
  } catch (e) {
    debugPrint('SchoolPickScreen: read persisted schools failed: $e');
    return [];
  }
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
