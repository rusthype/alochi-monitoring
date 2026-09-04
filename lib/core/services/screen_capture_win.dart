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

const int kFrameWidth = 320;
const int kFrameHeight = 180;
// ponytail: fixed JPEG quality — make adaptive only if a real 30-PC lab
// shows bandwidth pressure.
const int kJpegQuality = 55;

/// Captures the primary display, downscaled to [kFrameWidth]x[kFrameHeight],
/// as JPEG bytes. Returns null on any GDI failure or off-Windows.
/// Encoding runs in [Isolate.run] so the exam UI never drops a frame.
Future<Uint8List?> captureScreenJpeg() async {
  if (Platform.isMacOS) return _captureMacOsJpeg();
  if (!Platform.isWindows) return null;
  final bgra = _grabBgra();
  if (bgra == null) return null;
  try {
    return await Isolate.run(() {
      final image = img.Image.fromBytes(
        width: kFrameWidth,
        height: kFrameHeight,
        bytes: bgra.buffer,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      );
      return img.encodeJpg(image, quality: kJpegQuality);
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
Future<Uint8List?> _captureMacOsJpeg() async {
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
      ['-z', '$kFrameHeight', '$kFrameWidth', tempPath],
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
Uint8List? _grabBgra() {
  final hScreen = GetDC(NULL);
  if (hScreen == 0) return null;
  var hdcMem = 0;
  var hBmp = 0;
  Pointer<BITMAPINFO>? bi;
  Pointer<Uint8>? buf;
  try {
    hdcMem = CreateCompatibleDC(hScreen);
    hBmp = CreateCompatibleBitmap(hScreen, kFrameWidth, kFrameHeight);
    if (hdcMem == 0 || hBmp == 0) return null;
    SelectObject(hdcMem, hBmp);
    SetStretchBltMode(hdcMem, HALFTONE);
    final screenW = GetSystemMetrics(SM_CXSCREEN);
    final screenH = GetSystemMetrics(SM_CYSCREEN);
    final ok = StretchBlt(hdcMem, 0, 0, kFrameWidth, kFrameHeight, hScreen, 0,
        0, screenW, screenH, SRCCOPY);
    if (ok == 0) return null;

    bi = calloc<BITMAPINFO>();
    bi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bi.ref.bmiHeader.biWidth = kFrameWidth;
    bi.ref.bmiHeader.biHeight = -kFrameHeight; // negative => top-down rows
    bi.ref.bmiHeader.biPlanes = 1;
    bi.ref.bmiHeader.biBitCount = 32;
    bi.ref.bmiHeader.biCompression = BI_RGB;

    const bufSize = kFrameWidth * kFrameHeight * 4;
    buf = calloc<Uint8>(bufSize);
    final lines =
        GetDIBits(hdcMem, hBmp, 0, kFrameHeight, buf, bi, DIB_RGB_COLORS);
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
