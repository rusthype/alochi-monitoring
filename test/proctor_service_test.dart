// test/proctor_service_test.dart
// Runs on the CI/dev machine's actual platform (macOS/Linux) — exercises
// only the non-Windows no-op paths of the live-proctoring services.
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/services/proctor_service.dart';
import 'package:alochi_monitoring/core/services/screen_capture_win.dart';

void main() {
  group('screen_capture_win (non-Windows)', () {
    test('captureScreenJpeg returns null, never throws', () async {
      expect(await captureScreenJpeg(), isNull);
    });

    test('isForegroundOurs returns true', () {
      expect(isForegroundOurs(), true);
    });

    test('monitorCount returns 1', () {
      expect(monitorCount(), 1);
    });
  });

  group('ProctorService (non-Windows)', () {
    test('start() is a no-op — no timer, no callback ever fires', () async {
      var locked = false;
      var extended = false;
      // NOT a cascade: `..onLock = () => locked = true` would parse the
      // trailing `..onExtendSeconds`/`..start()` as chained off the arrow
      // body's `true` (a bool), not off ProctorService.instance — plain
      // statements avoid that ambiguity entirely.
      final proctor = ProctorService.instance;
      proctor.onLock = () => locked = true;
      proctor.onExtendSeconds = (_) => extended = true;
      proctor.start();
      await Future.delayed(const Duration(milliseconds: 200));
      expect(locked, false);
      expect(extended, false);
      ProctorService.instance.stop();
    });

    test('stop() twice in a row does not throw', () {
      ProctorService.instance.stop();
      expect(() => ProctorService.instance.stop(), returnsNormally);
    });
  });
}
