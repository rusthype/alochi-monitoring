import 'package:alochi_monitoring/core/services/heartbeat_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final hb = HeartbeatService.instance;
  late List<bool> locks;
  late List<int> extends_;
  late List<String> warnings;
  var keyframes = 0;

  setUp(() {
    // cancelTest() resets the private lock/extra-time baseline.
    hb.cancelTest();
    locks = [];
    extends_ = [];
    warnings = [];
    keyframes = 0;
    hb
      ..onLockChanged = locks.add
      ..onExtendSeconds = extends_.add
      ..onWarning = warnings.add
      ..onRequestKeyframe = () => keyframes++;
  });

  tearDown(() {
    hb
      ..onLockChanged = null
      ..onExtendSeconds = null
      ..onWarning = null
      ..onRequestKeyframe = null;
  });

  test('locked fires only on change (idempotent)', () {
    hb.reconcileProctorState(locked: true);
    hb.reconcileProctorState(locked: true);
    hb.reconcileProctorState(locked: false);
    hb.reconcileProctorState(locked: false);
    hb.reconcileProctorState();
    expect(locks, [true, false]);
  });

  test('extra_time is a cumulative total: only the delta is emitted', () {
    hb.reconcileProctorState(extraTimeSeconds: 300);
    hb.reconcileProctorState(extraTimeSeconds: 300); // replay
    hb.reconcileProctorState(extraTimeSeconds: 900);
    hb.reconcileProctorState(extraTimeSeconds: 0); // 0 == "no extra" -> -900
    expect(extends_, [300, 600, -900]);
  });

  test('commands: warning (trimmed, blank ignored) and request_keyframe', () {
    hb.reconcileProctorState(commands: [
      {'action': 'warning', 'message': '  Diqqat  '},
      {'action': 'warning', 'message': '   '},
      {'action': 'request_keyframe'},
      {'action': 'unknown'},
      'garbage',
    ]);
    expect(warnings, ['Diqqat']);
    expect(keyframes, 1);
  });

  test('empty/null commands are a no-op', () {
    hb.reconcileProctorState(commands: null);
    hb.reconcileProctorState(commands: const []);
    expect(warnings, isEmpty);
    expect(keyframes, 0);
  });

  // NOTE: `terminated` is handled in HeartbeatService._ping (it needs a real
  // sessionPing response), not in reconcileProctorState — not unit-testable
  // without an HTTP seam, which this codebase does not have.
}
