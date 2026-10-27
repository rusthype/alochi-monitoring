// lib/core/diagnostics/active_test_gate.dart
//
// Global "a student test is in progress" flag. Test runners hold it while
// mounted (mixin below); DeviceCommandClient defers a remote force-update
// while it is set so a student is never kicked out mid-test.
import 'package:flutter/widgets.dart';

class ActiveTestGate {
  ActiveTestGate._();

  /// True while at least one runner holds the gate.
  static final ValueNotifier<bool> active = ValueNotifier<bool>(false);
  static int _holders = 0;

  /// Takes the gate; the returned release is idempotent. Counting (not a
  /// plain bool) because a pushReplacement mounts the next runner before the
  /// previous one disposes.
  static void Function() enter() {
    _holders++;
    active.value = true;
    var released = false;
    return () {
      if (released) return;
      released = true;
      if (--_holders <= 0) {
        _holders = 0;
        active.value = false;
      }
    };
  }

  @visibleForTesting
  static void resetForTest() {
    _holders = 0;
    active.value = false;
  }
}

/// Add to a runner's State (`with ActiveTestGateHold`): holds the gate from
/// initState to dispose. Call [releaseTestGate] earlier once the attempt is
/// finished but the screen stays up (result display).
mixin ActiveTestGateHold<T extends StatefulWidget> on State<T> {
  void Function()? _releaseGate;

  @override
  void initState() {
    super.initState();
    _releaseGate = ActiveTestGate.enter();
  }

  void releaseTestGate() => _releaseGate?.call();

  @override
  void dispose() {
    releaseTestGate();
    super.dispose();
  }
}
