// lib/core/services/window_kiosk_linux.dart
// Linux window helpers backed by the GTK method channel "uz.alochi/window"
// (linux/runner/my_application.cc). Every function is a safe no-op off Linux
// and when the native side is missing (e.g. `flutter test`), so call sites in
// window_kiosk_win.dart / screen_capture_win.dart need only a Platform guard.
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart'
    show debugPrint, kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

const MethodChannel _channel = MethodChannel('uz.alochi/window');

// ponytail: one GTK window per process, so the focus flag is one module-level
// bool (same justification as _isFullscreen in window_kiosk_win.dart). Native
// pushes "activeChanged"; defaults to true so a missing native side never
// reads as "focus lost" to the proctor.
bool _active = true;
bool _handlerInstalled = false;

bool get _supported => !kIsWeb && Platform.isLinux;

/// Last focus state pushed by GTK (true until the first change).
bool get linuxWindowActive => _active;

@visibleForTesting
void setLinuxWindowActiveForTesting(bool v) => _active = v;

void _ensureHandler() {
  if (_handlerInstalled) return;
  _handlerInstalled = true;
  _channel.setMethodCallHandler((call) async {
    if (call.method == 'activeChanged' && call.arguments is bool) {
      _active = call.arguments as bool;
    }
    return null;
  });
}

Future<T?> _invoke<T>(String method, [Object? args]) async {
  if (!_supported) return null;
  _ensureHandler();
  try {
    return await _channel.invokeMethod<T>(method, args);
  } on MissingPluginException {
    return null; // native side absent (tests / older runner)
  } catch (e) {
    debugPrint('window channel $method failed: $e');
    return null;
  }
}

void linuxMaximize() => _invoke<void>('maximize');
void linuxToggleFullscreen() => _invoke<bool>('toggleFullscreen');
void linuxPresent() => _invoke<void>('present');
void linuxInhibitSleep(bool on) => _invoke<bool>('inhibitSleep', on);

/// Installs the focus listener and reads the initial focus state.
Future<void> linuxInitWindowState() async {
  final v = await _invoke<bool>('isActive');
  if (v != null) _active = v;
}
