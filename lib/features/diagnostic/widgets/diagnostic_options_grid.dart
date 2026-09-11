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
      // Two content-sized rows instead of GridView.count(childAspectRatio:
      // ...): a fixed aspect ratio forces every cell to a guessed height
      // that doesn't match the tactile card's actual (much shorter) content
      // height, leaving a large empty strip of the card's background "3D
      // edge" exposed below it (visually confirmed on a real run — the
      // guessed ratio was ~2x too tall). Row+Expanded sizes each row to its
      // children's real height, so there's no guesswork and no gap.
      return Column(
        children: [
          Row(
            children: [
              Expanded(child: cards[0]),
              const SizedBox(width: 14),
              Expanded(child: cards[1]),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(child: cards[2]),
              const SizedBox(width: 14),
              Expanded(child: cards[3]),
            ],
          ),
        ],
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
