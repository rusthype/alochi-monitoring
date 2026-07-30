// lib/core/services/heartbeat_service.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../api/api_client.dart';

class HeartbeatService with WidgetsBindingObserver {
  HeartbeatService._();
  static final HeartbeatService instance = HeartbeatService._();

  static const Duration _interval = Duration(seconds: 30);
  static const String _prefsKey = 'monitoring_session_id';

  Timer? _timer;
  bool _started = false;
  // Persistent, per-device id (survives across app restarts) — used for
  // idle/online presence heartbeats when no test is in progress.
  String? _deviceSessionId;
  // Fresh id minted per startTest() call — each test attempt gets its own
  // MonitoringSession row, so `started_at` reflects when THIS test began
  // rather than being frozen at first-ever app launch (see
  // apps/monitoring/models.py MonitoringSession.started_at, auto_now_add).
  String? _testSessionId;
  String? get _activeSessionId => _testSessionId ?? _deviceSessionId;
  String _schoolCode = '';
  String _name = '';
  String _variant = '';
  String _testKey = '';
  String? _studentCode;
  int _tabSwitchCount = 0;
  int? _currentQuestionIndex;
  int? _totalQuestions;
  List<int>? _questionTimes;

  String? _cachedPlatform;
  String? _cachedAppVersion;
  String? _cachedDeviceName;

  Future<void> _resolveDeviceInfoOnce() async {
    if (_cachedPlatform != null) return; // resolved once per process lifetime
    _cachedPlatform = Platform.isWindows
        ? 'windows'
        : Platform.isMacOS
            ? 'macos'
            : Platform.isLinux
                ? 'linux'
                : Platform.isAndroid
                    ? 'android'
                    : Platform.isIOS
                        ? 'ios'
                        : '';
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedAppVersion = info.buildNumber.isNotEmpty
          ? '${info.version}+${info.buildNumber}'
          : info.version;
    } catch (_) {
      _cachedAppVersion = '';
    }
    // The actual computer's own name (e.g. Windows "DESKTOP-AB12CD3" or a
    // school-assigned PC name) — lets an admin tell which physical machine
    // a live session belongs to, unlike the generic desktop/mobile/tablet
    // device_type bucket.
    try {
      _cachedDeviceName = Platform.localHostname;
    } catch (_) {
      _cachedDeviceName = '';
    }
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_prefsKey, id);
    }
    _deviceSessionId = id;
    WidgetsBinding.instance.addObserver(this);
    _timer = Timer.periodic(_interval, (_) => _ping('active'));
    unawaited(_ping('active'));
  }

  void startTest({
    required String schoolCode,
    required String name,
    required String variant,
    required String testKey,
    String? studentCode,
  }) {
    _testSessionId = const Uuid().v4();
    _schoolCode = schoolCode;
    _name = name;
    _variant = variant;
    _testKey = testKey;
    _studentCode = studentCode;
    _tabSwitchCount = 0;
    unawaited(_ping('active'));
  }

  void finishTest() {
    if (_testSessionId == null) return;
    unawaited(_ping('finished'));
    _testSessionId = null;
    _schoolCode = '';
    _name = '';
    _variant = '';
    _testKey = '';
    _studentCode = null;
    _tabSwitchCount = 0;
    _currentQuestionIndex = null;
    _totalQuestions = null;
    _questionTimes = null;
  }

  void updateProgress(
      int currentQuestionIndex, int totalQuestions, List<int> questionTimes) {
    _currentQuestionIndex = currentQuestionIndex;
    _totalQuestions = totalQuestions;
    _questionTimes = questionTimes;
  }

  Future<void> _ping(String status) async {
    final id = _activeSessionId;
    if (id == null) return;
    await _resolveDeviceInfoOnce();
    try {
      await api.sessionPing(
        sessionId: id,
        schoolCode: _schoolCode,
        name: _name,
        variant: _variant,
        testKey: _testKey,
        status: status,
        studentCode: _studentCode,
        tabSwitchCount: _tabSwitchCount,
        currentQuestionIndex: _currentQuestionIndex,
        totalQuestions: _totalQuestions,
        questionTimes: _questionTimes,
        platform: _cachedPlatform,
        appVersion: _cachedAppVersion,
        deviceName: _cachedDeviceName,
      );
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.detached ||
        state == AppLifecycleState.paused) {
      unawaited(_ping('finished'));
    } else if (state == AppLifecycleState.resumed) {
      if (_testKey.isNotEmpty) {
        _tabSwitchCount++;
      }
      unawaited(_ping('active'));
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    WidgetsBinding.instance.removeObserver(this);
    _started = false;
  }
}
