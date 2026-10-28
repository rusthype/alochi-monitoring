// lib/features/diagnostic/widgets/school_picker_body.dart
//
// Shared full-screen school picker UI (frame + search/city-chips/grouped
// pill-card body + error banner). Used by the diagnostic kiosk picker and the
// monitoring login picker; both only differ in where the schools come from and
// what a tap does.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/locale/locale_provider.dart';
import '../../../core/utils/student_name_formatter.dart';
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_school_list.dart';
import 'diagnostic_school_card.dart';
import 'diagnostic_widgets.dart';

/// Scaffold + floating [DiagnosticTopBar] + centered scrolling column.
class SchoolPickerFrame extends StatelessWidget {
  final String topBarTitle;
  final bool loading;
  final List<Widget> children;
  const SchoolPickerFrame({
    super.key,
    required this.topBarTitle,
    required this.loading,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: loading
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
                            children: children,
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
                  child: DiagnosticTopBar(title: topBarTitle),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline error card with a retry button.
class SchoolPickerErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const SchoolPickerErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.errorMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_rounded, color: AppColors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: AppColors.error,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(l10n.retry)),
        ],
      ),
    );
  }
}

/// Search field, city chips, last-chosen pinned card and city-grouped pill
/// cards. Owns the search/city state; [schools] must already be sorted.
class SchoolPickerBody extends StatefulWidget {
  final List<DiagnosticSchool> schools;
  final void Function(DiagnosticSchool) onSelect;

  /// [DiagnosticSchool.id] of the last chosen school (pinned first); '' = none.
  final String lastId;
  const SchoolPickerBody({
    super.key,
    required this.schools,
    required this.onSelect,
    this.lastId = '',
  });

  @override
  State<SchoolPickerBody> createState() => _SchoolPickerBodyState();
}

class _SchoolPickerBodyState extends State<SchoolPickerBody> {
  String _query = '';
  String? _city; // null = all

  Widget _card(
    DiagnosticSchool s,
    AppLocalizations l10n,
    Locale locale, {
    bool pinned = false,
    bool showCity = true,
  }) {
    return DiagnosticSchoolCard(
      number: s.number,
      title: shortSchoolName(
        s,
        locale,
        (n) => l10n.diagnosticSchoolNumberName(n),
      ),
      subtitle: !showCity || s.cityName.isEmpty
          ? null
          : toDisplayScript(s.cityName, locale),
      marker: pinned ? l10n.diagnosticSchoolLastChosen : null,
      onTap: () => widget.onSelect(s),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = ProviderScope.containerOf(
      context,
      listen: false,
    ).read(localeProvider);
    final schools = widget.schools;
    final cities = distinctCities(schools);
    final showChips = cities.length >= 2;
    final city = showChips && cities.contains(_city) ? _city : null;
    final shown = schools
        .where(
          (s) =>
              schoolMatchesQuery(s, _query) &&
              (city == null || s.cityName == city),
        )
        .toList();
    DiagnosticSchool? pinned;
    if (widget.lastId.isNotEmpty) {
      for (final s in shown) {
        if (s.id == widget.lastId) pinned = s;
      }
    }
    final rest = shown.where((s) => s != pinned).toList();

    // Group by city (insertion order == sorted order of first school);
    // city-less schools go to "Other" last. A single/absent city => no headers.
    final groups = <String, List<DiagnosticSchool>>{};
    for (final s in rest) {
      groups.putIfAbsent(s.cityName, () => []).add(s);
    }
    // Stable order: by first school number overall, not by search-result order.
    final keys = distinctCities(schools).where(groups.containsKey).toList();
    if (groups.containsKey('')) keys.add('');
    final headers = showChips;

    Widget wrap(List<Widget> kids) =>
        Wrap(spacing: 12, runSpacing: 12, children: kids);
    // One school (e.g. offline USB mode): nothing to search or filter.
    final showSearch = schools.length > 1;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
          wrap([
            for (final s in groups[k]!)
              _card(s, l10n, locale, showCity: !headers),
          ]),
          const SizedBox(height: 20),
        ],
      ],
    );
  }
}
