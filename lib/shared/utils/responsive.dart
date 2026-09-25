// lib/shared/utils/responsive.dart
//
// Shared sizing helpers for small school monitors (1024x768, 1280x720,
// 1366x768) where exam-runner screens with hardcoded image heights push
// answer options / nav buttons off-screen.
import 'package:flutter/widgets.dart';

/// True on short screens (school monitors), where fixed-height images need
/// to shrink to keep answers/nav buttons on-screen.
bool isCompact(BuildContext context) => MediaQuery.sizeOf(context).height < 750;

/// A media (question image) height scaled to the screen, clamped to
/// [min, max]. Defaults match the 240px diagnostic question-card image;
/// pass tighter bounds for smaller images.
double clampedMediaHeight(
  BuildContext context, {
  double factor = 0.26,
  double min = 90.0,
  double max = 240.0,
}) {
  return (MediaQuery.sizeOf(context).height * factor).clamp(min, max);
}
