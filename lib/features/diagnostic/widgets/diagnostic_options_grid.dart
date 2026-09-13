// lib/features/diagnostic/widgets/diagnostic_options_grid.dart
//
// Lays out fixed-variant answer options as a 2x2 grid of tactile cards when
// all 4 options' text actually fits within 2 lines at the real per-card text
// width (measured with TextPainter against DiagnosticTactileOptionCard's
// live chrome and the ambient font-scale setting — see MediaQuery.textScalerOf
// below), otherwise falls back to a single-column stack — same tactile card
// either way. CAT flow doesn't use this; it keeps rendering
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

  static const _rowGap = 14.0; // SizedBox between the two Expanded cards

  static bool _fitsTwoLines(
      String text, double textWidth, TextScaler textScaler) {
    if (textWidth <= 0) return false;
    final painter = TextPainter(
      text: TextSpan(
          text: text, style: DiagnosticTactileOptionCard.optionTextStyle),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
      maxLines: 2,
    )..layout(maxWidth: textWidth);
    return !painter.didExceedMaxLines;
  }

  /// [textWidth] is the usable width for the option text inside one
  /// 2-column card, derived from the dock's real available width.
  /// [textScaler] must be the ambient ("Katta shrift" setting) scaler the
  /// card will actually render with — omitting it (default: no scaling)
  /// would pick a grid at 1.0x that then overflows to 3 lines once the
  /// user's font-scale preference is applied, since the card itself never
  /// clips or shrinks the text.
  static bool shouldUseGrid(
    List<DiagnosticOptionItem> options,
    double textWidth, {
    TextScaler textScaler = TextScaler.noScaling,
  }) =>
      options.length == 4 &&
      options.every((o) => _fitsTwoLines(o.text, textWidth, textScaler));

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
            DiagnosticTactileOptionCard.horizontalPadding -
            DiagnosticTactileOptionCard.badgeReserve -
            DiagnosticTactileOptionCard.checkmarkReserve;
        final textScaler = MediaQuery.textScalerOf(context);

        if (shouldUseGrid(options, textWidth, textScaler: textScaler)) {
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
