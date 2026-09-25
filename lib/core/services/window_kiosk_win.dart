// lib/core/services/window_kiosk_win.dart
// Windows-only kiosk fullscreen: strips the window's caption/border via win32
// and resizes it to cover the primary monitor. No native C++, no method
// channel — same pure-Dart-FFI style as screen_capture_win.dart. A safe
// no-op on every other platform (and on web), so call sites never need their
// own Platform.isWindows guard.
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:win32/win32.dart';

const int _kFullscreenStyleMask = WS_CAPTION | WS_THICKFRAME;

// ponytail: single kiosk window per process (same "one mutable global"
// justification as currentCaptureProfile in screen_capture_win.dart) — no DI
// container exists to thread this through. Resets on relaunch.
int _hwnd = 0;
int? _savedStyle;
int _savedLeft = 0, _savedTop = 0, _savedWidth = 0, _savedHeight = 0;
bool _isFullscreen = false;

@visibleForTesting
bool get isFullscreenForTesting => _isFullscreen;

/// True once [enterKioskFullscreen] or [toggleFullscreen] has resolved a
/// window handle to operate on.
bool get _hasWindow {
  if (_hwnd != 0) return true;
  final hwnd = GetForegroundWindow();
  if (hwnd == 0) return false;
  _hwnd = hwnd;
  return true;
}

/// Call once, right after `runApp`, to switch the kiosk window to a
/// frameless, full-monitor state. No-op on non-Windows/web, or if already
/// fullscreen.
void enterKioskFullscreen() {
  if (kIsWeb || !Platform.isWindows) return;
  if (_isFullscreen) return;
  if (!_hasWindow) return;
  _applyFullscreen(_hwnd);
}

/// F11 handler: flips between frameless-fullscreen and the previously saved
/// windowed style/rect. No-op on non-Windows/web.
void toggleFullscreen() {
  if (kIsWeb || !Platform.isWindows) return;
  if (!_hasWindow) return;
  if (_isFullscreen) {
    _restoreWindowed(_hwnd);
  } else {
    _applyFullscreen(_hwnd);
  }
}

void _applyFullscreen(int hwnd) {
  final rect = calloc<RECT>();
  try {
    _savedStyle = GetWindowLongPtr(hwnd, GWL_STYLE);
    if (GetWindowRect(hwnd, rect) != 0) {
      _savedLeft = rect.ref.left;
      _savedTop = rect.ref.top;
      _savedWidth = rect.ref.right - rect.ref.left;
      _savedHeight = rect.ref.bottom - rect.ref.top;
    }
  } finally {
    calloc.free(rect);
  }

  SetWindowLongPtr(
    hwnd,
    GWL_STYLE,
    _savedStyle! & ~_kFullscreenStyleMask,
  );

  final width = GetSystemMetrics(SM_CXSCREEN);
  final height = GetSystemMetrics(SM_CYSCREEN);
  SetWindowPos(
    hwnd,
    HWND_TOP,
    0,
    0,
    width,
    height,
    SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOOWNERZORDER,
  );
  _isFullscreen = true;
}

void _restoreWindowed(int hwnd) {
  final savedStyle = _savedStyle;
  if (savedStyle != null) {
    SetWindowLongPtr(hwnd, GWL_STYLE, savedStyle);
  }
  SetWindowPos(
    hwnd,
    HWND_TOP,
    _savedLeft,
    _savedTop,
    _savedWidth,
    _savedHeight,
    SWP_FRAMECHANGED | SWP_NOZORDER | SWP_NOOWNERZORDER,
  );
  _isFullscreen = false;
}
