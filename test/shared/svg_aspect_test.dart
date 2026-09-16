import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/shared/utils/svg_aspect.dart';

void main() {
  test('parses aspect ratio from viewBox', () {
    expect(
      svgAspectRatio('<svg viewBox="0 0 180 95"><rect/></svg>'),
      closeTo(180 / 95, 0.001),
    );
  });

  test('returns null when viewBox is absent', () {
    expect(svgAspectRatio('<svg width="10" height="10"></svg>'), isNull);
  });

  test('returns null for malformed/zero-height viewBox', () {
    expect(svgAspectRatio('<svg viewBox="0 0 180 0"></svg>'), isNull);
  });
}
