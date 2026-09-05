// test/proctor_service_test.dart
// Runs on the CI/dev machine's actual platform — on this repo's dev
// machines that is macOS, where captureScreenJpeg() now actually shells out
// to `screencapture`/`sips` (see screen_capture_win.dart's macOS branch)
// instead of being a guaranteed no-op like on Linux/other platforms. The
// old assumption that captureScreenJpeg() always returns null no longer
// holds here, so this file can no longer hard-assert isNull.
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/services/proctor_service.dart';
import 'package:alochi_monitoring/core/services/screen_capture_win.dart';

void main() {
  group('screen_capture_win', () {
    test(
      'captureScreenJpeg never throws and completes',
      () async {
        // On macOS this genuinely runs `screencapture` + `sips`. It returns
        // real JPEG bytes when the test runner (terminal) has been granted
        // Screen Recording permission, or null when it hasn't — both are
        // legitimate outcomes on a dev/CI Mac, so we can't hard-assert
        // either one. What we CAN assert unconditionally: it never throws,
        // and if it does return bytes, they look like a real downscaled
        // JPEG rather than garbage.
        final capture = await captureScreenJpeg();
        if (capture != null) {
          expect(capture.jpeg, isNotEmpty);
          // Sanity bound only — this is not the server's real 30KB
          // enforcement (already covered by the backend test suite), just
          // a guard against capturing something absurdly large here.
          expect(capture.jpeg.length, lessThan(500 * 1024));
        }
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );

    test('isForegroundOurs returns true', () {
      expect(isForegroundOurs(), true);
    });

    test('monitorCount returns 1', () {
      expect(monitorCount(), 1);
    });

    test(
      'resetCaptureStreamForNewSession rotates the stream epoch',
      () async {
        // Guards against the actual Stage 2a hotfix regressing: if
        // resetCaptureStreamForNewSession() were removed or stopped
        // reassigning _streamEpoch, this would fail because the epoch
        // would stay identical across the two calls.
        resetCaptureStreamForNewSession();
        final first = currentStreamEpochForTesting;
        // Epoch is millis-since-epoch mod 1e6, so two back-to-back calls
        // can collide within the same millisecond — a tiny delay makes the
        // second call land in a different millisecond deterministically.
        await Future.delayed(const Duration(milliseconds: 5));
        resetCaptureStreamForNewSession();
        final second = currentStreamEpochForTesting;
        expect(second, isNot(equals(first)));
      },
    );

    test('macOS capture cooldown blocks repeated spawns after a failure', () {
      final now = DateTime.now();
      setMacOsCaptureCooldownForTesting(now.add(const Duration(seconds: 30)));
      expect(macOsCaptureOnCooldownForTesting(now), isTrue);
      expect(
        macOsCaptureOnCooldownForTesting(now.add(const Duration(seconds: 31))),
        isFalse,
      );
    });
  });

  group('ProctorService', () {
    test(
      'start() with no active session/token never fires callbacks',
      () async {
        // ProctorService._tick() reads HeartbeatService.instance.proctorToken
        // and .activeSessionId and bails out (reschedule-only, no capture,
        // no callback) before touching onLock/onExtendSeconds whenever
        // either is null. No session token is set up in this test, so this
        // holds on every platform where start() arms the timer at all
        // (Windows and now macOS) — verified by reading _tick()'s early
        // return above the capture/API call.
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
        await Future.delayed(const Duration(milliseconds: 300));
        expect(locked, false);
        expect(extended, false);
        ProctorService.instance.stop();
      },
    );

    test('stop() twice in a row does not throw', () {
      ProctorService.instance.stop();
      expect(() => ProctorService.instance.stop(), returnsNormally);
    });
  });
}
