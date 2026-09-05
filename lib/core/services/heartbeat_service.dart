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

  /// Public read-only surface for other features that need to tag their own
  /// telemetry (e.g. question_report_sheet.dart) with the same session id
  /// this service is already pinging under. Deliberately just a getter —
  /// never call anything here that would mutate ping/conflict/terminated
  /// state; that stays owned by [startTest]/[cancelTest]/[finishTest].
  String? get activeSessionId => _activeSessionId;

  String? _proctorToken;
  int _proctorIntervalMs = 2500;

  /// Per-session HMAC handed back by the ping response, consumed by
  /// ProctorService. Null until the first successful ping of a test session.
  String? get proctorToken => _proctorToken;
  int get proctorIntervalMs => _proctorIntervalMs;

  /// Public read-only progress surface for ProctorService (avoids
  /// duplicating question-index/total state that this service already owns).
  int? get currentQuestionIndex => _currentQuestionIndex;
  int? get totalQuestions => _totalQuestions;
  String? get currentQuestionText => _currentQuestionText;
  String? get selectedOptionText => _selectedOptionText;

  String _schoolCode = '';
  String _name = '';
  String _variant = '';
  String _testKey = '';
  String? _studentCode;
  int _tabSwitchCount = 0;
  int? _currentQuestionIndex;
  int? _totalQuestions;
  List<int>? _questionTimes;
  String? _currentQuestionText;
  String? _selectedOptionText;

  String? _cachedPlatform;
  String? _cachedAppVersion;
  String? _cachedDeviceName;

  /// Set by whichever screen is currently showing an active test
  /// (`_TestEngineState.initState`), cleared on its `dispose`. Invoked when
  /// a ping response comes back with `terminated: true` — i.e. an admin
  /// ended this device's session remotely via the panel — so the active
  /// test surface can force-exit exactly like a timeout auto-submit
  /// (see `_TestEngineState._finishNow`). Null when no test is in progress;
  /// the pre-test roster/catalog screens never set this.
  VoidCallback? onTerminated;

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

  /// Starts a new test session and fires its immediate ping, returning
  /// whether it is safe to proceed to the test screen.
  ///
  /// Returns `false` ONLY when the ping succeeded and the backend
  /// explicitly reported `conflict: true` (another device already holds an
  /// active session for this student_code+test_key). Returns `true` both
  /// when there is no conflict AND when the ping fails/throws — this check
  /// is best-effort and must never block offline test-taking.
  Future<bool> startTest({
    required String schoolCode,
    required String name,
    required String variant,
    required String testKey,
    String? studentCode,
  }) async {
    _testSessionId = const Uuid().v4();
    _schoolCode = schoolCode;
    _name = name;
    _variant = variant;
    _testKey = testKey;
    _studentCode = studentCode;
    _tabSwitchCount = 0;
    final response = await _ping('active');
    return !(response != null && response['conflict'] == true);
  }

  /// Reverts local state after a [startTest] call whose immediate ping came
  /// back with `conflict: true` — no MonitoringSession row was actually
  /// created server-side for that session id, so it must not linger as
  /// `_testSessionId`, or every subsequent idle-presence heartbeat (the
  /// app-wide 30s timer from [start]) would keep targeting a session that
  /// doesn't exist. Local-only, fires no network request. Callers must only
  /// invoke this when they did NOT proceed to the test screen — once a test
  /// is actually launched, `_testSessionId` must stay put for the rest of
  /// the attempt regardless of how the conflict check resolved.
  void cancelTest() {
    _testSessionId = null;
    _schoolCode = '';
    _name = '';
    _variant = '';
    _testKey = '';
    _studentCode = null;
    _tabSwitchCount = 0;
    _proctorToken = null;
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
    _currentQuestionText = null;
    _selectedOptionText = null;
    _proctorToken = null;
  }

  /// Login qilgan talaba identitini idle-presence heartbeat'ga (start()
  /// tomonidan app ishga tushganda boshlanadigan) biriktiradi — shu bilan
  /// panelning "kutayotganlar" ro'yxatida faqat qurilma nomi o'rniga
  /// ism/maktab ko'rinadi. Yangi sessiya id yaratmaydi — talaba hali test
  /// boshlamagan, shuning uchun mavjud _deviceSessionId ping'iga qo'shiladi.
  /// group_name ataylab yuborilmaydi: LiveMonitoringView uni server tomonda
  /// Student.student_groups orqali student_code asosida aniqroq hisoblaydi.
  void setStudentContext({
    required String schoolCode,
    required String name,
    String? studentCode,
  }) {
    _schoolCode = schoolCode;
    _name = name;
    _studentCode = studentCode;
    unawaited(_ping('active'));
  }

  /// setStudentContext() bilan o'rnatilgan identitini tozalaydi — logout
  /// paytida chaqiriladi, shu bilan umumiy kioskdagi keyingi talaba oldingi
  /// talabaning ismi/maktabini idle heartbeat'da meros qilib olmaydi.
  void clearStudentContext() {
    _schoolCode = '';
    _name = '';
    _studentCode = null;
    unawaited(_ping('active'));
  }

  void updateProgress(
      int currentQuestionIndex, int totalQuestions, List<int> questionTimes,
      [String? currentQuestionText, String? selectedOptionText]) {
    _currentQuestionIndex = currentQuestionIndex;
    _totalQuestions = totalQuestions;
    _questionTimes = questionTimes;
    _currentQuestionText = currentQuestionText;
    _selectedOptionText = selectedOptionText;
  }

  Future<Map<String, dynamic>?> _ping(String status) async {
    final id = _activeSessionId;
    if (id == null) return null;
    await _resolveDeviceInfoOnce();
    try {
      final response = await api.sessionPing(
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
      // `terminated` is returned on every ping for a session an admin ended
      // remotely via the panel (not just the one that caused it), so this
      // check runs on every ping call site, not only the 30s heartbeat.
      if (response['terminated'] == true) {
        onTerminated?.call();
      }
      final tok = response['proctor_token'];
      if (tok is String && tok.isNotEmpty) _proctorToken = tok;
      final iv = response['proctor_interval_ms'];
      if (iv is int && iv >= 1000 && iv <= 30000) _proctorIntervalMs = iv;
      return response;
    } catch (_) {
      return null;
    }
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
