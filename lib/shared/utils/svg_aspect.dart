// lib/shared/utils/svg_aspect.dart
//
// flutter_svg/vector_graphics falls back to a 100x100 intrinsic size when
// the root <svg> has no explicit width/height attribute (viewBox-only SVGs,
// which is how the backend emits diagnostic diagrams). That square fallback
// then gets stretched by BoxFit.contain into whatever box a caller passes,
// skewing any non-square viewBox (e.g. "0 0 180 95") into a square. Passing
// an explicit `width` derived from the real viewBox aspect ratio avoids the
// square fallback entirely.
final _viewBoxRe =
    RegExp(r'viewBox\s*=\s*"([\d.\-]+)[ ,]+([\d.\-]+)[ ,]+([\d.\-]+)[ ,]+([\d.\-]+)"');

/// Returns width/height from the SVG's viewBox, or null if absent/invalid.
double? svgAspectRatio(String svg) {
  final match = _viewBoxRe.firstMatch(svg);
  if (match == null) return null;
  final w = double.tryParse(match.group(3)!);
  final h = double.tryParse(match.group(4)!);
  if (w == null || h == null || h == 0) return null;
  return w / h;
}
