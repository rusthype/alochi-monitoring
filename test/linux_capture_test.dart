import 'dart:io';

import 'package:alochi_monitoring/core/services/screen_capture_win.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

/// Fake tool runner: tools in [working] write a real PNG to the output path
/// and exit 0, tools in [failing] exit 1, everything else is "not installed".
class _Fake {
  _Fake({this.working = const {}, this.failing = const {}});
  final Set<String> working;
  final Set<String> failing;
  final calls = <String>[];

  Future<int> call(String exe, List<String> args) async {
    calls.add(exe);
    if (failing.contains(exe)) return 1;
    if (!working.contains(exe)) throw ProcessException(exe, args, 'nf', 2);
    final out = args.last;
    final im = img.Image(width: 200, height: 100);
    img.fill(im, color: img.ColorRgb8(200, 30, 30));
    File(out).writeAsBytesSync(img.encodePng(im));
    return 0;
  }
}

void main() {
  late Directory tmp;
  setUp(() {
    resetLinuxCaptureForTesting();
    tmp = Directory.systemTemp.createTempSync('linuxcap');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  test('candidate order: Wayland vs X11, output path', () {
    final w = linuxCaptureCandidates('/o.png');
    expect(w.map((e) => e.$1), ['gnome-screenshot', 'grim', 'scrot', 'import']);
    expect(w.every((e) => e.$2.contains('/o.png')), isTrue);
    final x = linuxCaptureCandidates('/o.png', x11: true);
    expect(x.map((e) => e.$1), ['scrot', 'import', 'gnome-screenshot', 'grim']);
  });

  test('falls through missing/failing tools to the first that works', () async {
    final f = _Fake(working: {'scrot'}, failing: {'gnome-screenshot'});
    final raw = await grabLinuxScreenFile(run: f.call, tmp: tmp, x11: false);
    expect(raw, isNotNull);
    expect(f.calls, ['gnome-screenshot', 'grim', 'scrot']);
    expect(tmp.listSync(), isEmpty, reason: 'temp file removed');
    // The working tool is remembered and tried first next time.
    f.calls.clear();
    await grabLinuxScreenFile(run: f.call, tmp: tmp, x11: false);
    expect(f.calls.first, 'scrot');
  });

  test('no tool installed: null, and later ticks stop spawning', () async {
    final f = _Fake();
    expect(
        await grabLinuxScreenFile(run: f.call, tmp: tmp, x11: false), isNull);
    expect(f.calls.length, 4);
    f.calls.clear();
    expect(
        await grabLinuxScreenFile(run: f.call, tmp: tmp, x11: false), isNull);
    expect(f.calls, isEmpty);
  });

  test('tools present but all failing is NOT permanent', () async {
    final f = _Fake(failing: {'gnome-screenshot', 'grim', 'scrot', 'import'});
    expect(
        await grabLinuxScreenFile(run: f.call, tmp: tmp, x11: false), isNull);
    f.calls.clear();
    expect(
        await grabLinuxScreenFile(run: f.call, tmp: tmp, x11: false), isNull);
    expect(f.calls, isNotEmpty);
  });

  test('captureLinuxJpeg returns a profile-sized keyframe JPEG', () async {
    final f = _Fake(working: {'gnome-screenshot'});
    final r =
        await captureLinuxJpeg(CaptureProfile.grid, run: f.call, tmp: tmp);
    expect(r, isNotNull);
    expect(r!.frameType, 'keyframe');
    expect((r.w, r.h), (640, 360));
    expect(r.cursorVisible, isFalse);
    final decoded = img.decodeJpg(r.jpeg)!;
    expect((decoded.width, decoded.height), (640, 360));
    expect(decoded.getPixel(10, 10).r, greaterThan(150));
  });

  test('captureLinuxJpeg: no tool -> null (no mock frame)', () async {
    final r = await captureLinuxJpeg(CaptureProfile.grid,
        run: _Fake().call, tmp: tmp);
    expect(r, isNull);
  });
}
