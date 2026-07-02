// lib/core/config/feature_flags.dart
// Runtime feature flags. Flip to true only after score-parity is verified.

/// When true, Unit1 is launched via the generic engine (EngineHostScreen)
/// instead of the hand-rolled Unit1Runner.
/// DEFAULT: false — zero live risk until parity is confirmed.
///
/// Scope note: this only gates unit1_screen.dart's guest-mode routing.
/// The roster-picker flow (student_entry_screen.dart -> runner_dispatch.dart)
/// is a separate product surface that already always routes through
/// TestEngine, unconditionally — that is not this flag and is not a bug.
const bool kUseEngineForUnit1 = false;
