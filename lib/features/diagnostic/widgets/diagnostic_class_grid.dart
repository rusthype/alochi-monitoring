// lib/features/diagnostic/widgets/diagnostic_class_grid.dart
//
// Kiosk class cards (step 2): same card as the school grid, laid out in a
// width-adaptive grid (columns grow with the window, cards stay 200-280 wide).
import 'package:flutter/material.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../shared/theme/app_theme.dart';
import 'diagnostic_school_card.dart';

const double _kMinCardWidth = 200;
const double _kGap = 12;
const int _kMaxColumns = 6;

/// Number of grid columns for [width] available pixels.
int diagnosticClassColumns(double width) =>
    ((width + _kGap) / (_kMinCardWidth + _kGap)).floor().clamp(1, _kMaxColumns);

/// Leading grade number of a class label ("3-A" -> 3), null when absent.
int? classGradeNumber(String label) {
  final m = RegExp(r'^\s*(\d+)').firstMatch(label);
  return m == null ? null : int.tryParse(m.group(1)!);
}

class DiagnosticClassGrid extends StatelessWidget {
  final List<Map<String, dynamic>> classes;

  /// Called for a normal class tap.
  final void Function(
    String classLabel,
    String language, {
    required bool hasWebTest,
    required String webTestKey,
  }) onSelect;

  /// Called instead of [onSelect] for a class flagged `no_tests`.
  final VoidCallback onNoTests;

  const DiagnosticClassGrid({
    super.key,
    required this.classes,
    required this.onSelect,
    required this.onNoTests,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final hasMultipleLanguages = classes
            .map((c) => (c['language'] ?? 'uz').toString().toLowerCase())
            .toSet()
            .length >
        1;
    return LayoutBuilder(builder: (context, box) {
      final cols = diagnosticClassColumns(box.maxWidth);
      final cardWidth = (box.maxWidth - _kGap * (cols - 1)) / cols;
      return Wrap(
        spacing: _kGap,
        runSpacing: _kGap,
        children: [
          for (final c in classes)
            () {
              final classLabel = (c['class_label'] ?? '').toString();
              final language = (c['language'] ?? 'uz').toString();
              final hasWebTest = c['has_web_test'] == true;
              final webTestKey = (c['web_test_key'] ?? '').toString();
              final isRu = language.toLowerCase() == 'ru';
              // Offline pack without tests for this class's grade: dimmed,
              // never opened.
              final noTests = c['no_tests'] == true;
              return Opacity(
                opacity: noTests ? 0.45 : 1,
                child: DiagnosticSchoolCard(
                  width: cardWidth,
                  number: classGradeNumber(classLabel),
                  icon: Icons.class_rounded,
                  title: classLabel,
                  subtitle: hasMultipleLanguages || isRu
                      ? (isRu ? l10n.languageRussian : l10n.languageUzbek)
                      : null,
                  trailing: hasWebTest
                      ? const Icon(Icons.public_rounded,
                          size: 16, color: AppColors.brand)
                      : null,
                  onTap: noTests
                      ? onNoTests
                      : () => onSelect(classLabel, language,
                          hasWebTest: hasWebTest, webTestKey: webTestKey),
                ),
              );
            }(),
        ],
      );
    });
  }
}
