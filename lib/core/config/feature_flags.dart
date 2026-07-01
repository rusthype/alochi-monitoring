// lib/core/config/feature_flags.dart
// Runtime feature flags. Flip to true only after score-parity is verified.

/// When true, Unit1 is launched via the generic engine (EngineHostScreen)
/// instead of the hand-rolled Unit1Runner.
/// DEFAULT: false — zero live risk until parity is confirmed.
const bool kUseEngineForUnit1 = false;
