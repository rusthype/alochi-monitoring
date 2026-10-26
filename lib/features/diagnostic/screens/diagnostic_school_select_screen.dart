// lib/features/diagnostic/screens/diagnostic_school_select_screen.dart
//
// Diagnostic kiosk flow — step 1: pick the school. Visual pattern copied
// (never imported) from lib/features/session/group_select_screen.dart's
// step-indicator/pill-grid layout; the PIN check copies
// session_setup_screen.dart's `_expectedPin`/`_confirm` logic verbatim
// (client-side-only UX deterrent, no network call for the check itself).
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart' show ApiException;
import '../../../core/locale/locale_provider.dart';
import '../../../core/utils/student_name_formatter.dart';
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_kiosk_api.dart';
import '../data/diagnostic_school_list.dart';
import '../widgets/diagnostic_school_card.dart';
import '../widgets/diagnostic_widgets.dart';

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
  String _query = '';
  String? _city; // null = all
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

  Widget _card(
    DiagnosticSchool s,
    AppLocalizations l10n,
    Locale locale, {
    bool pinned = false,
  }) {
    return DiagnosticSchoolCard(
      number: s.number,
      title: shortSchoolName(
        s,
        locale,
        (n) => l10n.diagnosticSchoolNumberName(n),
      ),
      subtitle: s.cityName.isEmpty ? null : toDisplayScript(s.cityName, locale),
      marker: pinned ? l10n.diagnosticSchoolLastChosen : null,
      onTap: () => _selectSchool(s.raw),
    );
  }

  List<Widget> _buildSchools(AppLocalizations l10n, Locale locale) {
    final cities = distinctCities(_schools);
    final showChips = cities.length >= 2;
    final city = showChips && cities.contains(_city) ? _city : null;
    final shown = _schools
        .where(
          (s) =>
              schoolMatchesQuery(s, _query) &&
              (city == null || s.cityName == city),
        )
        .toList();
    DiagnosticSchool? pinned;
    if (_lastId.isNotEmpty) {
      for (final s in shown) {
        if (s.id == _lastId) pinned = s;
      }
    }
    final rest = shown.where((s) => s != pinned).toList();

    // Group by city (insertion order == sorted order of first school);
    // city-less schools go to "Other" last. A single/absent city => no headers.
    final groups = <String, List<DiagnosticSchool>>{};
    for (final s in rest) {
      groups.putIfAbsent(s.cityName, () => []).add(s);
    }
    final keys = groups.keys.where((k) => k.isNotEmpty).toList();
    if (groups.containsKey('')) keys.add('');
    final headers = showChips;

    Widget wrap(List<Widget> kids) =>
        Wrap(spacing: 12, runSpacing: 12, children: kids);
    // One school (e.g. offline USB mode): nothing to search or filter.
    final showSearch = _schools.length > 1;
    return [
      if (showSearch)
        TextField(
          onChanged: (v) => setState(() => _query = v),
          style: const TextStyle(fontSize: 18),
          decoration: InputDecoration(
            hintText: l10n.diagnosticSchoolSearchHint,
            prefixIcon: const Icon(Icons.search_rounded),
            filled: true,
            fillColor: AppColors.surface,
            contentPadding: const EdgeInsets.symmetric(vertical: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: AppColors.border),
            ),
          ),
        ),
      if (showChips) ...[
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final c in [null, ...cities]) ...[
                DiagnosticPillButton(
                  label: c == null
                      ? l10n.diagnosticSchoolAll
                      : toDisplayScript(c, locale),
                  isSelected: city == c,
                  onTap: () => setState(() => _city = c),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
      if (showSearch) const SizedBox(height: 20),
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Text(
            l10n.diagnosticSchoolNoMatches,
            style: const TextStyle(fontSize: 16, color: AppColors.ink3),
          ),
        ),
      if (pinned != null) ...[
        wrap([_card(pinned, l10n, locale, pinned: true)]),
        const SizedBox(height: 20),
      ],
      for (final k in keys) ...[
        if (headers)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              k.isEmpty
                  ? l10n.diagnosticSchoolOther
                  : toDisplayScript(k, locale),
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppColors.ink2,
              ),
            ),
          ),
        wrap([for (final s in groups[k]!) _card(s, l10n, locale)]),
        const SizedBox(height: 20),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider);
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
                        top: 90,
                        bottom: 40,
                        left: 16,
                        right: 16,
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1040),
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
                              if (_error == null && _fromCache)
                                const DiagnosticOfflineBadge(),
                              if (_error != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.errorMuted,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.error.withValues(
                                        alpha: 0.2,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.warning_rounded,
                                        color: AppColors.error,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: const TextStyle(
                                            color: AppColors.error,
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 40,
                                  ),
                                  child: Text(
                                    l10n.diagnosticNoSchools,
                                    style: const TextStyle(
                                      fontSize: 16,
                                      color: AppColors.ink3,
                                    ),
                                  ),
                                )
                              else
                                ..._buildSchools(l10n, locale),
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
