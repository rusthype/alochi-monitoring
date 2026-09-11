// lib/features/diagnostic/widgets/diagnostic_options_grid.dart
//
// Lays out fixed-variant answer options as a 2x2 grid of tactile cards when
// all 4 options are short (numeric-style answers, e.g. "25"), otherwise
// falls back to a single-column stack — same tactile card either way. CAT
// flow doesn't use this; it keeps rendering `DiagnosticOptionCard` directly.
import 'package:flutter/material.dart';
import '../data/diagnostic_option_item.dart';
import 'diagnostic_tactile_option_card.dart';

class DiagnosticOptionsGrid extends StatelessWidget {
  final List<DiagnosticOptionItem> options;
  final String? selectedOption;

  /// false disables tap handling (e.g. while a submit is in flight).
  final bool interactive;
  final ValueChanged<String> onSelect;

  const DiagnosticOptionsGrid({
    super.key,
    required this.options,
    required this.selectedOption,
    required this.interactive,
    required this.onSelect,
  });

  /// 8 chars comfortably covers numeric/short-word answers (e.g. "154",
  /// "3+7") without wrapping inside a 2-column card; anything longer (a
  /// sentence-style option) falls back to the single-column list below,
  /// where a card can use the full row width.
  static const _shortAnswerMaxLength = 8;

  static bool shouldUseGrid(List<DiagnosticOptionItem> options) =>
      options.length == 4 &&
      options.every((o) => o.text.length <= _shortAnswerMaxLength);

  @override
  Widget build(BuildContext context) {
    final cards = options
        .map((o) => DiagnosticTactileOptionCard(
              label: o.key,
              text: o.text,
              selected: selectedOption == o.key,
              onTap: interactive ? () => onSelect(o.key) : () {},
            ))
        .toList();

    if (shouldUseGrid(options)) {
      return GridView.count(
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        // Wide+short (2.2:1) so a short numeric answer's tactile card reads
        // as a tappable button, not a tall tile.
        childAspectRatio: 2.2,
        mainAxisSpacing: 14,
        crossAxisSpacing: 14,
        children: cards,
      );
    }

    return Column(
      children: [
        for (final card in cards)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: card),
      ],
    );
  }
}
