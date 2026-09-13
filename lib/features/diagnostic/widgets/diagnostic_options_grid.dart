// lib/features/diagnostic/widgets/diagnostic_options_grid.dart
//
// Lays out fixed-variant answer options as a 2x2 grid of tactile cards when
// all 4 options' text actually fits within 2 lines at the real per-card text
// width (measured with TextPainter against DiagnosticTactileOptionCard's
// live chrome), otherwise falls back to a single-column stack — same
// tactile card either way. CAT flow doesn't use this; it keeps rendering
// `DiagnosticOptionCard` directly.
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

  /// Must match DiagnosticTactileOptionCard's unselected option-text style
  /// (fontSize 15, FontWeight.w500) — the selected weight (w700) is
  /// deliberately not used here, since the grid-vs-list decision must not
  /// flip when an option becomes selected mid-interaction.
  static const _optionTextStyle =
      TextStyle(fontSize: 15, fontWeight: FontWeight.w500);

  static const _rowGap = 14.0; // SizedBox between the two Expanded cards
  static const _cardHorizontalPadding =
      14.0 * 2; // card's EdgeInsets.symmetric(horizontal: 14)
  static const _badgeReserve = 36.0 + 10.0; // letter badge width + its gap
  // Checkmark reserved even when unselected (SizedBox(width: 8) +
  // Container(width: 22)), so the grid/list decision can't flip between an
  // option's selected and unselected render — see class doc.
  static const _checkmarkReserve = 8.0 + 22.0;

  static bool _fitsTwoLines(String text, double textWidth) {
    if (textWidth <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(text: text, style: _optionTextStyle),
      textDirection: TextDirection.ltr,
      maxLines: 2,
    )..layout(maxWidth: textWidth);
    return !painter.didExceedMaxLines;
  }

  /// [textWidth] is the usable width for the option text inside one
  /// 2-column card, derived from the dock's real available width.
  static bool shouldUseGrid(
          List<DiagnosticOptionItem> options, double textWidth) =>
      options.length == 4 &&
      options.every((o) => _fitsTwoLines(o.text, textWidth));

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = (constraints.maxWidth - _rowGap) / 2;
        final textWidth = columnWidth -
            _cardHorizontalPadding -
            _badgeReserve -
            _checkmarkReserve;

        if (shouldUseGrid(options, textWidth)) {
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
                  const SizedBox(width: _rowGap),
                  Expanded(child: cards[1]),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(child: cards[2]),
                  const SizedBox(width: _rowGap),
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
      },
    );
  }
}
