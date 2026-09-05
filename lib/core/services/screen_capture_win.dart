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

/// Captures the primary display, downscaled to [currentCaptureProfile]'s
/// width/height, as JPEG bytes at its quality. Returns null on any GDI
/// failure or off-Windows. Encoding runs in [Isolate.run] so the exam UI
/// never drops a frame.
Future<Uint8List?> captureScreenJpeg() async {
  final profile = currentCaptureProfile; // snapshot before isolate/CLI hop
  if (Platform.isMacOS) return _captureMacOsJpeg(profile);
  if (!Platform.isWindows) return null;
  final bgra = _grabBgra(profile);
  if (bgra == null) return null;
  final width = profile.width;
  final height = profile.height;
  final quality = profile.quality;
  try {
    return await Isolate.run(() {
      final image = img.Image.fromBytes(
        width: width,
        height: height,
        bytes: bgra.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      return img.encodeJpg(image, quality: quality);
    });
  } catch (_) {
    return null;
  }
}

/// macOS capture via the `screencapture` + `sips` CLI tools (already present
/// on every Mac, no FFI/native code/entitlement changes needed — the kiosk's
/// app-sandbox entitlement is already false). `screencapture -x -m -t jpg`
/// grabs the main display silently to a temp file; `sips -z H W` downscales
/// it in place to the same wire size the Windows path emits. Every failure
/// (missing Screen Recording permission, missing binaries, timeout) is a
/// null return, matching the Windows contract.
Future<Uint8List?> _captureMacOsJpeg(CaptureProfile profile) async {
  final tempPath =
      '${Directory.systemTemp.path}/proctor_${DateTime.now().microsecondsSinceEpoch}.jpg';
  final tempFile = File(tempPath);
  try {
    final capRes = await Process.run(
      'screencapture',
      ['-x', '-m', '-t', 'jpg', tempPath],
    ).timeout(const Duration(seconds: 2));
    if (capRes.exitCode != 0 || !await tempFile.exists()) return null;

    final sipsRes = await Process.run(
      'sips',
      ['-z', '${profile.height}', '${profile.width}', tempPath],
    ).timeout(const Duration(seconds: 2));
    if (sipsRes.exitCode != 0) return null;

    return await tempFile.readAsBytes();
  } catch (_) {
    return null;
  } finally {
    if (await tempFile.exists()) {
      try {
        await tempFile.delete();
      } catch (_) {}
    }
  }
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
    final screenW = GetSystemMetrics(SM_CXSCREEN);
    final screenH = GetSystemMetrics(SM_CYSCREEN);
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
