// lib/core/services/screen_capture_win.dart
// Live proctoring (Windows kiosk): GDI screen capture via pure Dart FFI.
// No native C++, no method channels — every function here is a safe
// no-op/default on non-Windows platforms, so call sites never need their
// own Platform.isWindows guard.
import 'dart:ffi';
import 'dart:io' show Directory, File, Platform, Process;
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kDebugMode, visibleForTesting;
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart';

class CaptureProfile {
  final int width;
  final int height;
  final int quality;
  const CaptureProfile._(this.width, this.height, this.quality);
  static const CaptureProfile grid = CaptureProfile._(640, 360, 68);
  static const CaptureProfile spotlight = CaptureProfile._(960, 540, 72);
}

// ponytail: mutable module-level current profile — captureScreenJpeg() reads
// this at call time; proctor_service.dart updates it from the backend's
// per-poll response (profile/target_width). Single kiosk process, single
// active test session, so a plain mutable global is the lazy-correct choice
// here (no DI container to thread a profile object through GDI/isolate
// boundaries for one value). In-memory only — resets to grid on relaunch.
CaptureProfile currentCaptureProfile = CaptureProfile.grid;

/// Result of one capture tick: the JPEG bytes plus enough metadata for the
/// backend to reassemble a patch onto its last-known keyframe and to render
/// the cursor without decoding pixels for it.
class CaptureResult {
  final Uint8List jpeg;
  final String frameType; // 'keyframe' | 'patch'
  final int x;
  final int y;
  final int w;
  final int h;
  final int streamEpoch;
  final int? cursorX;
  final int? cursorY;
  final bool cursorVisible;
  const CaptureResult({
    required this.jpeg,
    required this.frameType,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.streamEpoch,
    this.cursorX,
    this.cursorY,
    this.cursorVisible = false,
  });
}

// ponytail: stream_epoch only needs to be stable for the life of this
// process and change across restarts — a millisecond timestamp mod 1e6
// satisfies that with zero persistence/coordination. Not a sequence number,
// just a restart marker the backend uses to discard stale patches.
int _streamEpoch = DateTime.now().millisecondsSinceEpoch % 1000000;

/// Test-only peek at the current stream epoch — proves
/// [resetCaptureStreamForNewSession] actually rotates it.
@visibleForTesting
int get currentStreamEpochForTesting => _streamEpoch;

// macOS-only permanent disable: once `screencapture`/`sips` fails once (the
// overwhelming common cause is a denied/pending Screen Recording TCC grant),
// never spawn another subprocess for the rest of this process's life. TCC
// dialogs are anchored to the process, so a timed retry (the previous fix)
// just re-shows the same system dialog every 30s forever — only a relaunch
// (after granting permission in System Settings) should re-arm capture.
bool _macOsCaptureDisabled = false;

// Debug-mode default: unless a developer explicitly opts in, never call
// `screencapture` at all when running locally via `flutter run` (kDebugMode
// is always false in a real `flutter build --release` Windows kiosk
// installer, so this can never affect production). Opt in with
// `ALOCHI_FORCE_MACOS_CAPTURE=1` in the environment before launch.
bool get _macOsCaptureAllowedInDebug =>
    !kDebugMode || Platform.environment['ALOCHI_FORCE_MACOS_CAPTURE'] == '1';

@visibleForTesting
void setMacOsCaptureDisabledForTesting(bool disabled) {
  _macOsCaptureDisabled = disabled;
}

@visibleForTesting
bool get macOsCaptureDisabledForTesting => _macOsCaptureDisabled;

// Dirty-rect diffing state (Windows only). Reset whenever the profile
// changes since grid<->spotlight switches dimensions, invalidating any
// byte-range comparison against the previous frame.
Uint8List? _lastFrameBgra;
CaptureProfile? _lastFrameProfile;
DateTime? _lastKeyframeAt;
bool _forceKeyframe = false;

/// Forces the NEXT capture to be a full keyframe. Called by
/// proctor_service.dart when the capture profile flips (grid<->spotlight)
/// or the backend requests one via action=='request_keyframe'.
void forceNextKeyframe() => _forceKeyframe = true;

/// Called once per new exam-session start (ProctorService.start()). Rotates
/// the stream epoch and clears cross-session dirty-rect state so the first
/// frame of a new session is always a full keyframe under a fresh epoch —
/// even when the kiosk process is reused back-to-back for two students.
void resetCaptureStreamForNewSession() {
  _streamEpoch = DateTime.now().millisecondsSinceEpoch % 1000000;
  _lastFrameBgra = null;
  _lastFrameProfile = null;
  _lastKeyframeAt = null;
  _forceKeyframe = true;
}

class _DirtyResult {
  final String frameType;
  final int x;
  final int y;
  final int w;
  final int h;
  const _DirtyResult(this.frameType, this.x, this.y, this.w, this.h);
}

const int _kDirtyTile = 64;
const Duration _kKeyframeInterval = Duration(seconds: 12);

bool _rowRangeEqual(Uint8List a, Uint8List b, int start, int length) {
  for (var i = 0; i < length; i++) {
    if (a[start + i] != b[start + i]) return false;
  }
  return true;
}

/// Decides whether this tick sends a full keyframe or a cropped patch, and
/// updates [_lastKeyframeAt] whenever a keyframe is actually produced.
_DirtyResult _decideDirty(CaptureProfile profile, Uint8List bgra) {
  final width = profile.width;
  final height = profile.height;
  final now = DateTime.now();
  final profileChanged = _lastFrameProfile != profile;
  final keyframeDue = _lastKeyframeAt == null ||
      now.difference(_lastKeyframeAt!) >= _kKeyframeInterval;

  if (_lastFrameBgra == null || profileChanged || keyframeDue || _forceKeyframe) {
    _forceKeyframe = false;
    _lastKeyframeAt = now;
    return _DirtyResult('keyframe', 0, 0, width, height);
  }

  final prev = _lastFrameBgra!;
  var minX = width, minY = height, maxX = 0, maxY = 0;
  var anyDirty = false;
  for (var ty = 0; ty < height; ty += _kDirtyTile) {
    final tileH = (ty + _kDirtyTile > height) ? height - ty : _kDirtyTile;
    for (var tx = 0; tx < width; tx += _kDirtyTile) {
      final tileW = (tx + _kDirtyTile > width) ? width - tx : _kDirtyTile;
      var dirty = false;
      for (var row = 0; row < tileH; row++) {
        final rowStart = ((ty + row) * width + tx) * 4;
        final rowLen = tileW * 4;
        if (!_rowRangeEqual(bgra, prev, rowStart, rowLen)) {
          dirty = true;
          break;
        }
      }
      if (dirty) {
        anyDirty = true;
        if (tx < minX) minX = tx;
        if (ty < minY) minY = ty;
        if (tx + tileW > maxX) maxX = tx + tileW;
        if (ty + tileH > maxY) maxY = ty + tileH;
      }
    }
  }

  if (!anyDirty) {
    // ponytail: zero dirty tiles still needs an upload this tick — the tick
    // loop in proctor_service.dart isn't built to skip uploads, and adding
    // that would ripple into its timer/backoff bookkeeping for a rare case
    // (a fully static screen). Sending a minimal 1-tile patch is simplest;
    // upgrade to a real skip-upload path if bandwidth ever matters.
    return _DirtyResult(
        'patch', 0, 0, _kDirtyTile.clamp(0, width), _kDirtyTile.clamp(0, height));
  }

  final dirtyW = maxX - minX;
  final dirtyH = maxY - minY;
  final coverage = (dirtyW * dirtyH) / (width * height);
  if (coverage < 0.30) {
    // ponytail: single bounding box, not full multi-rect merge — a scattered
    // diff (e.g. cursor in one corner + text change in another) still ships
    // as one rect covering both, which can be larger than the true dirty
    // area but is far simpler than tracking/encoding a rect list.
    return _DirtyResult('patch', minX, minY, dirtyW, dirtyH);
  }
  _lastKeyframeAt = now;
  return _DirtyResult('keyframe', 0, 0, width, height);
}

/// Shared by [_grabBgra] and [_getCursorPosition] so both use the identical
/// screen-size values for their downscale/coordinate-scale math.
(int, int) _getScreenSize() {
  final w = GetSystemMetrics(SM_CXSCREEN);
  final h = GetSystemMetrics(SM_CYSCREEN);
  return (w, h);
}

/// Absolute cursor position converted into [profile]'s downscaled
/// coordinate space, reusing the exact scale factor [_grabBgra] uses for its
/// StretchBlt call. Returns invisible when off the captured monitor
/// entirely (e.g. cursor parked on a secondary monitor).
(int x, int y, bool visible) _getCursorPosition(CaptureProfile profile) {
  if (!Platform.isWindows) return (0, 0, false);
  final point = calloc<POINT>();
  try {
    if (GetCursorPos(point) == 0) return (0, 0, false);
    final rawX = point.ref.x;
    final rawY = point.ref.y;
    final (screenW, screenH) = _getScreenSize();
    if (screenW <= 0 || screenH <= 0) return (0, 0, false);
    if (rawX < 0 || rawX > screenW || rawY < 0 || rawY > screenH) {
      return (0, 0, false);
    }
    final scaledX =
        (rawX * profile.width / screenW).round().clamp(0, profile.width);
    final scaledY =
        (rawY * profile.height / screenH).round().clamp(0, profile.height);
    return (scaledX, scaledY, true);
  } finally {
    calloc.free(point);
  }
}

/// Captures the primary display, downscaled to [currentCaptureProfile]'s
/// width/height, as a [CaptureResult] (JPEG bytes + dirty-rect/cursor
/// metadata). Returns null on any GDI failure or off-Windows/macOS.
/// Encoding runs in [Isolate.run] so the exam UI never drops a frame.
Future<CaptureResult?> captureScreenJpeg() async {
  final profile = currentCaptureProfile; // snapshot before isolate/CLI hop
  if (Platform.isMacOS) return _captureMacOsJpeg(profile);
  if (!Platform.isWindows) return null;
  final bgra = _grabBgra(profile);
  if (bgra == null) return null;
  final width = profile.width;
  final height = profile.height;
  final quality = profile.quality;

  final dirty = _decideDirty(profile, bgra);
  final cursor = _getCursorPosition(profile);

  // Stash this tick's raw frame for the NEXT tick's diff, regardless of
  // whether this tick itself was a keyframe or a patch.
  _lastFrameBgra = bgra;
  _lastFrameProfile = profile;

  try {
    final jpeg = await Isolate.run(() {
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: bgra.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      final target = dirty.frameType == 'keyframe'
          ? image
          : img.copyCrop(image,
              x: dirty.x, y: dirty.y, width: dirty.w, height: dirty.h);
      return img.encodeJpg(target, quality: quality);
    });
    return CaptureResult(
      jpeg: jpeg,
      frameType: dirty.frameType,
      x: dirty.x,
      y: dirty.y,
      w: dirty.w,
      h: dirty.h,
      streamEpoch: _streamEpoch,
      cursorX: cursor.$1,
      cursorY: cursor.$2,
      cursorVisible: cursor.$3,
    );
  } catch (_) {
    return null;
  }
}

/// macOS capture via the `screencapture` + `sips` CLI tools (already present
/// on every Mac, no FFI/native code/entitlement changes needed — the kiosk's
/// app-sandbox entitlement is already false). `screencapture -x -m -t jpg`
/// grabs the main display silently to a temp file; `sips -z H W` downscales
/// it in place to the same wire size the Windows path emits. The FIRST
/// failure (missing Screen Recording permission, missing binaries, timeout)
/// permanently disables real capture for the rest of this process's life —
/// see [_macOsCaptureDisabled] — and every subsequent call (including this
/// one, mid-failure) returns [_mockMacOsFrame] instead of retrying
/// `screencapture`, so the TCC "would like to record this screen" dialog
/// never resurfaces after the first Allow/Deny.
///
/// Stage 2a scope: dirty-rect diffing and cursor capture are Windows-only.
/// macOS always produces a full-frame keyframe with no cursor data — an
/// accepted gap since macOS is dev-only here, not a production kiosk
/// platform.
Future<CaptureResult?> _captureMacOsJpeg(CaptureProfile profile) async {
  if (_macOsCaptureDisabled || !_macOsCaptureAllowedInDebug) {
    return _mockMacOsFrame(profile);
  }

  final tempPath =
      '${Directory.systemTemp.path}/proctor_${DateTime.now().microsecondsSinceEpoch}.jpg';
  final tempFile = File(tempPath);
  try {
    final capRes = await Process.run(
      'screencapture',
      ['-x', '-m', '-t', 'jpg', tempPath],
    ).timeout(const Duration(seconds: 2));
    if (capRes.exitCode != 0 || !await tempFile.exists()) {
      _macOsCaptureDisabled = true;
      return _mockMacOsFrame(profile);
    }

    final sipsRes = await Process.run(
      'sips',
      ['-z', '${profile.height}', '${profile.width}', tempPath],
    ).timeout(const Duration(seconds: 2));
    if (sipsRes.exitCode != 0) {
      _macOsCaptureDisabled = true;
      return _mockMacOsFrame(profile);
    }

    final jpeg = await tempFile.readAsBytes();
    return CaptureResult(
      jpeg: jpeg,
      frameType: 'keyframe',
      x: 0,
      y: 0,
      w: profile.width,
      h: profile.height,
      streamEpoch: _streamEpoch,
      cursorVisible: false,
    );
  } catch (_) {
    _macOsCaptureDisabled = true;
    return _mockMacOsFrame(profile);
  } finally {
    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }
}

Uint8List? _mockFrameCache;
CaptureProfile? _mockFrameProfile;

/// Lightweight solid-color placeholder JPEG for macOS local dev when real
/// screen capture is disabled (by default in debug mode, or permanently
/// after a TCC-denied failure) — keeps the panel receiving frames instead of
/// going blank, without ever touching a screen-recording API. Encoded once
/// per capture profile and cached; a static image needs no per-tick isolate
/// hop.
CaptureResult _mockMacOsFrame(CaptureProfile profile) {
  if (_mockFrameCache == null || _mockFrameProfile != profile) {
    final image = img.Image(width: profile.width, height: profile.height);
    img.fill(image, color: img.ColorRgb8(30, 30, 34));
    _mockFrameCache =
        Uint8List.fromList(img.encodeJpg(image, quality: profile.quality));
    _mockFrameProfile = profile;
  }
  return CaptureResult(
    jpeg: _mockFrameCache!,
    frameType: 'keyframe',
    x: 0,
    y: 0,
    w: profile.width,
    h: profile.height,
    streamEpoch: _streamEpoch,
    cursorVisible: false,
  );
}

/// Raw BGRA pixel grab via GDI StretchBlt+GetDIBits. Synchronous, must run
/// on the UI isolate (touches GDI handles). Every handle is freed in a
/// finally block — a leak here compounds at ~24 calls/minute and eventually
/// exhausts the process's GDI handle quota.
Uint8List? _grabBgra(CaptureProfile profile) {
  final width = profile.width;
  final height = profile.height;
  final hScreen = GetDC(NULL);
  if (hScreen == 0) return null;
  var hdcMem = 0;
  var hBmp = 0;
  Pointer<BITMAPINFO>? bi;
  Pointer<Uint8>? buf;
  try {
    hdcMem = CreateCompatibleDC(hScreen);
    hBmp = CreateCompatibleBitmap(hScreen, width, height);
    if (hdcMem == 0 || hBmp == 0) return null;
    SelectObject(hdcMem, hBmp);
    SetStretchBltMode(hdcMem, HALFTONE);
    final (screenW, screenH) = _getScreenSize();
    final ok = StretchBlt(hdcMem, 0, 0, width, height, hScreen, 0,
        0, screenW, screenH, SRCCOPY);
    if (ok == 0) return null;

    bi = calloc<BITMAPINFO>();
    bi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bi.ref.bmiHeader.biWidth = width;
    bi.ref.bmiHeader.biHeight = -height; // negative => top-down rows
    bi.ref.bmiHeader.biPlanes = 1;
    bi.ref.bmiHeader.biBitCount = 32;
    bi.ref.bmiHeader.biCompression = BI_RGB;

    final bufSize = width * height * 4;
    buf = calloc<Uint8>(bufSize);
    final lines =
        GetDIBits(hdcMem, hBmp, 0, height, buf, bi, DIB_RGB_COLORS);
    if (lines == 0) return null;
    return Uint8List.fromList(buf.asTypedList(bufSize)); // copy before free
  } catch (_) {
    return null;
  } finally {
    if (buf != null) calloc.free(buf);
    if (bi != null) calloc.free(bi);
    if (hBmp != 0) DeleteObject(hBmp);
    if (hdcMem != 0) DeleteDC(hdcMem);
    ReleaseDC(NULL, hScreen);
  }
}

/// True when the foreground window belongs to THIS process — i.e. our exam
/// window (or any auxiliary window we own) currently has focus. Compares
/// process IDs rather than HWNDs: this app exposes no MethodChannel handing
/// its own HWND to Dart, and a process-ID check is strictly more robust
/// anyway (an HWND check would false-positive "focus lost" on our own
/// tooltips/dialogs, which are separate HWNDs of the same process).
bool isForegroundOurs() {
  if (!Platform.isWindows) return true;
  final hwnd = GetForegroundWindow();
  if (hwnd == 0) return false;
  final pidPtr = calloc<Uint32>();
  try {
    GetWindowThreadProcessId(hwnd, pidPtr);
    return pidPtr.value == GetCurrentProcessId();
  } finally {
    calloc.free(pidPtr);
  }
}

/// Physical monitor count. 1 = normal; >1 is reported as a passive signal
/// (never blocks the student).
int monitorCount() {
  if (!Platform.isWindows) return 1;
  final n = GetSystemMetrics(SM_CMONITORS);
  return n > 0 ? n : 1;
}
