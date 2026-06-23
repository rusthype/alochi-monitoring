// test/engine/svg_text_render_test.dart
// Golden test: confirms that flutter_svg renders <text> elements (clock
// numerals, schema numbers) as visible pixels in the output PNG.
//
// Loads a real TTF (DejaVuSans) to eliminate the headless-font confound:
// in flutter test, all text becomes Ahem (box glyphs) unless a real font
// is registered via FontLoader.
//
// Run with:  flutter test --update-goldens test/engine/svg_text_render_test.dart
// Then:      flutter test test/engine/svg_text_render_test.dart

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';

// Real SVG strings extracted from prod fixture math_diag_3_4, variant "1".

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

// Loads DejaVuSans (or Liberation Sans fallback) into the Flutter test engine
// under every family name that SVG font-family="sans-serif" might resolve to.
// Without this every glyph renders as Ahem (a filled box) in headless mode.
Future<void> _loadRealFont() async {
  const candidates = [
    '/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',
    '/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf',
  ];
  String? chosen;
  for (final path in candidates) {
    if (File(path).existsSync()) {
      chosen = path;
      break;
    }
  }
  if (chosen == null) return; // nothing we can do in this env

  final bytes = File(chosen).readAsBytesSync().buffer.asByteData();
  for (final family in [
    'sans-serif',
    'DejaVu Sans',
    'Liberation Sans',
    'Roboto'
  ]) {
    final loader = FontLoader(family)..addFont(Future.value(bytes));
    await loader.load();
  }
}

Widget _wrapSvg(String svgString, double w, double h) {
  return MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: SvgPicture.string(svgString, width: w, height: h),
      ),
    ),
  );
}

Widget _wrapText() {
  return const MaterialApp(
    home: Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Text(
          '12345',
          style: TextStyle(
            fontSize: 24,
            color: Colors.black,
            fontFamily: 'sans-serif',
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(_loadRealFont);

  group('SVG <text> golden render (real font)', () {
    testWidgets('reference — plain Text("12345") font-load proof',
        (tester) async {
      await tester.pumpWidget(_wrapText());
      await tester.pump();
      await expectLater(
        find.byType(Text),
        matchesGoldenFile('goldens/text_reference.png'),
      );
    });

    testWidgets('clock — renders 12/3/6/9 labels', (tester) async {
      await tester.pumpWidget(_wrapSvg(_svgClock, 200, 200));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      await expectLater(
        find.byType(SvgPicture),
        matchesGoldenFile('goldens/svg_clock.png'),
      );
    });

    testWidgets('schema — renders 34, ÷2, ?, ×6 labels', (tester) async {
      await tester.pumpWidget(_wrapSvg(_svgSchema, 400, 100));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      await expectLater(
        find.byType(SvgPicture),
        matchesGoldenFile('goldens/svg_schema.png'),
      );
    });
  });
}
