// test/engine/svg_text_render_test.dart
// Golden test: confirms that flutter_svg renders <text> elements (clock
// numerals, schema numbers) as visible pixels in the output PNG.
//
// Run with:  flutter test --update-goldens test/engine/svg_text_render_test.dart
// Then:      flutter test test/engine/svg_text_render_test.dart
//
// After running --update-goldens, READ the PNGs with the Read tool and confirm
// that the numbers (12, 3, 6, 9 for the clock; 34, ?, ×6 for the schema) are
// actually visible — that is the definitive <text> render check.

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

// Real SVG strings extracted from prod fixture math_diag_3_4, variant "1".

// Clock: <circle> face + <text> labels 12 / 3 / 6 / 9 + two clock hands.
const _svgClock =
    '<svg width="90" height="90" viewBox="0 0 90 90" xmlns="http://www.w3.org/2000/svg">'
    '<circle cx="45" cy="45" r="40" fill="#EEF4FF" stroke="#1A237E" stroke-width="2"/>'
    '<text x="45" y="12" text-anchor="middle" font-size="9" font-weight="800" fill="#333" font-family="sans-serif">12</text>'
    '<text x="78" y="49" text-anchor="middle" font-size="9" font-weight="800" fill="#333" font-family="sans-serif">3</text>'
    '<text x="45" y="82" text-anchor="middle" font-size="9" font-weight="800" fill="#333" font-family="sans-serif">6</text>'
    '<text x="12" y="49" text-anchor="middle" font-size="9" font-weight="800" fill="#333" font-family="sans-serif">9</text>'
    '<line x1="45" y1="45" x2="66.8" y2="47.9" stroke="#E65100" stroke-width="3" stroke-linecap="round"/>'
    '<line x1="45" y1="45" x2="78.0" y2="45.0" stroke="#1A237E" stroke-width="1.8" stroke-linecap="round"/>'
    '<circle cx="45" cy="45" r="3" fill="#333"/>'
    '</svg>';

// Schema (number chain): rect boxes + <text> numbers/operators (34, ÷2, ?, ×6).
const _svgSchema =
    '<svg width="300" height="48" viewBox="0 0 300 48" xmlns="http://www.w3.org/2000/svg">'
    '<rect x="2" y="6" width="50" height="30" rx="7" fill="#EEF4FF" stroke="#4B7BE5" stroke-width="1.5"/>'
    '<text x="27" y="26" text-anchor="middle" font-size="13" font-weight="700" fill="#1a3a8f" font-family="sans-serif">34</text>'
    '<text x="66" y="26" text-anchor="middle" font-size="14" fill="#555" font-family="sans-serif">→</text>'
    '<rect x="78" y="6" width="50" height="30" rx="7" fill="#E8F5E9" stroke="#388E3C" stroke-width="1.5"/>'
    '<text x="103" y="26" text-anchor="middle" font-size="12" font-weight="700" fill="#1b5e20" font-family="sans-serif">÷2</text>'
    '<text x="142" y="26" text-anchor="middle" font-size="14" fill="#555" font-family="sans-serif">→</text>'
    '<rect x="154" y="6" width="50" height="30" rx="7" fill="#FFF8E1" stroke="#F9A825" stroke-width="1.5"/>'
    '<text x="179" y="26" text-anchor="middle" font-size="13" font-weight="700" fill="#e65100" font-family="sans-serif">?</text>'
    '<text x="218" y="26" text-anchor="middle" font-size="14" fill="#555" font-family="sans-serif">→</text>'
    '<rect x="230" y="6" width="50" height="30" rx="7" fill="#FCE4EC" stroke="#E91E63" stroke-width="1.5"/>'
    '<text x="255" y="26" text-anchor="middle" font-size="12" font-weight="700" fill="#880E4F" font-family="sans-serif">×6</text>'
    '</svg>';

Widget _wrap(String svgString, double w, double h) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SvgPicture.string(
          svgString,
          width: w,
          height: h,
        ),
      ),
    ),
  );
}

void main() {
  group('SVG <text> golden render', () {
    testWidgets('clock — renders 12/3/6/9 labels', (tester) async {
      await tester.pumpWidget(_wrap(_svgClock, 200, 200));
      // Give vector_graphics time to finish async compilation
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      await expectLater(
        find.byType(SvgPicture),
        matchesGoldenFile('goldens/svg_clock.png'),
      );
    });

    testWidgets('schema — renders 34, ÷2, ?, ×6 labels', (tester) async {
      await tester.pumpWidget(_wrap(_svgSchema, 400, 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      await expectLater(
        find.byType(SvgPicture),
        matchesGoldenFile('goldens/svg_schema.png'),
      );
    });
  });
}
