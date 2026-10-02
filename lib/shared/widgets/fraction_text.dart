import 'package:flutter/material.dart';

// Matches `a/b` and mixed `w a/b` that are not glued to letters, digits,
// other slashes or a decimal tail (so dates, "km/h", 1/2/3 stay plain).
final RegExp _fractionRe =
    RegExp(r'(?<![\w/.])(?:(\d+)[  ])?(\d+)/(\d+)(?![\w/]|\.\d)');

/// Renders [text] like `Text`, but `a/b` / `w a/b` tokens become stacked
/// fractions (numerator over a bar over denominator). Text without any
/// fraction is returned as a plain `Text` (identical to the old rendering).
class FractionText extends StatelessWidget {
  final String text;
  final TextStyle? style;

  const FractionText(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) {
    final matches = _fractionRe
        .allMatches(text)
        .where((m) => int.parse(m.group(3)!) != 0)
        .toList();
    if (matches.isEmpty) return Text(text, style: style);

    final base = DefaultTextStyle.of(context).style.merge(style);
    final size = base.fontSize ?? 14;
    final fracStyle = base.copyWith(fontSize: size * 0.8, height: 1.1);
    final barColor = base.color ?? Colors.black;

    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final whole = m.group(1);
      final stacked = IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(m.group(2)!, style: fracStyle, textAlign: TextAlign.center),
            Container(
                height: 1.2,
                margin: const EdgeInsets.symmetric(vertical: 1),
                color: barColor),
            Text(m.group(3)!, style: fracStyle, textAlign: TextAlign.center),
          ],
        ),
      );
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: whole == null
            ? Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: stacked)
            : Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(whole, style: base),
                    const SizedBox(width: 3),
                    stacked,
                  ],
                ),
              ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return Text.rich(TextSpan(children: spans), style: style);
  }
}
