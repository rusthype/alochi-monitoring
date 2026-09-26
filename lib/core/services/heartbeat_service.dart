// lib/core/services/heartbeat_service.dart
import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../api/api_client.dart';
import '../network/network_info.dart';

class HeartbeatService with WidgetsBindingObserver {
  HeartbeatService._();
  static final HeartbeatService instance = HeartbeatService._();

  static const Duration _interval = Duration(seconds: 30);
  static const String _prefsKey = 'monitoring_session_id';

  /// Declared on every ping so the backend knows this build understands the
  /// `locked`/`extra_time_seconds`/`commands` reply fields (see
  /// [reconcileProctorState]) and the seat-binding `machine_id`/`mac_address`
  /// request fields — an older kiosk build that omits this list still gets
  /// served the legacy top-level `{"action":"lock"}` command instead.
  static const List<String> _capabilities = ['pause_lock', 'seat_id'];

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
  Map<String, dynamic>? _answers;
  int? _elapsedSeconds;

  String? _cachedPlatform;
  String? _cachedAppVersion;
  String? _cachedDeviceName;
  String? _cachedMachineId;
  String? _cachedMacAddress;

  /// Set by whichever screen is currently showing an active test
  /// (`_TestEngineState.initState`), cleared on its `dispose`. Invoked when
  /// a ping response comes back with `terminated: true` — i.e. an admin
  /// ended this device's session remotely via the panel — so the active
  /// test surface can force-exit exactly like a timeout auto-submit
  /// (see `_TestEngineState._finishNow`). Null when no test is in progress;
  /// the pre-test roster/catalog screens never set this.
  VoidCallback? onTerminated;

  // ── Admin-lock (pause) + extra-time reconciliation ──────────────────────
  // Both channels that can carry this state — this 30s ping AND
  // ProctorService's ~2.5s frame ingest — funnel through
  // [reconcileProctorState] so there is exactly one canonical `_locked`/
  // `_extraTimeBaseline`, however either arrives first. Reset per test
  // attempt (see startTest/cancelTest/finishTest) since extra_time_seconds
  // is cumulative for the CURRENT subject/test only.
  bool _locked = false;
  int _extraTimeBaseline = 0;

  /// Fired when the reconciled admin-lock (pause) state changes.
  ValueChanged<bool>? onLockChanged;

  /// Fired with the DELTA of seconds to add to the countdown — never the
  /// raw server value, which is a cumulative total for the current
  /// subject/test, not a delta. Diffing against the last-seen baseline here
  /// means a duplicate/replayed ping or frame response (same cumulative
  /// value) is a no-op instead of double-adding time.
  ValueChanged<int>? onExtendSeconds;

  ValueChanged<String>? onWarning;

  /// Fired for a `request_keyframe` command — set by ProctorService (the
  /// owner of the actual capture stream) while it's running, cleared when
  /// it stops.
  VoidCallback? onRequestKeyframe;

  /// Applies the `locked`/`extra_time_seconds`/`commands` fields the
  /// backend returns on every ping AND every proctor frame response.
  /// Idempotent: calling it twice with the same values fires no callbacks
  /// the second time, so a reconnect/duplicate response can't double-pause
  /// or double-add time.
  void reconcileProctorState({
    bool? locked,
    int? extraTimeSeconds,
    List<dynamic>? commands,
  }) {
    if (locked != null && locked != _locked) {
      _locked = locked;
      onLockChanged?.call(locked);
    }
    if (extraTimeSeconds != null) {
      final delta = extraTimeSeconds - _extraTimeBaseline;
      if (delta != 0) {
        _extraTimeBaseline = extraTimeSeconds;
        onExtendSeconds?.call(delta);
      }
    }
    if (commands == null || commands.isEmpty) return;
    for (final cmd in commands) {
      if (cmd is! Map) continue;
      switch (cmd['action']) {
        case 'warning':
          final msg = cmd['message'];
          if (msg is String && msg.trim().isNotEmpty) {
            onWarning?.call(msg.trim());
          }
        case 'request_keyframe':
          onRequestKeyframe?.call();
      }
    }
  }

  void _resetProctorState() {
    _locked = false;
    _extraTimeBaseline = 0;
  }

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
    // Seat-binding identity (Windows only; both already cache themselves
    // per app-run in network_info.dart, so this just triggers that once).
    _cachedMachineId = machineGuid();
    _cachedMacAddress = await primaryMac();
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
    _resetProctorState(); // fresh pause/extra-time baseline for this attempt
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
    _resetProctorState();
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
    _answers = null;
    _elapsedSeconds = null;
    _resetProctorState();
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

  /// Called by TestEngine on every answer change (power-outage-tolerant
  /// live sync). Fire-and-forget — fires an immediate ping carrying the
  /// full answers map + foreground-active elapsed seconds, instead of
  /// waiting up to 30s for the periodic timer, so a student who loses
  /// power mid-test can resume on any PC via SessionResumeView. Must never
  /// be awaited by the caller (answer-tap callback stays non-blocking).
  void reportAnswers(Map<String, dynamic> answers, int elapsedSeconds) {
    _answers = answers;
    _elapsedSeconds = elapsedSeconds;
    unawaited(_ping('active'));
  }

  Future<Map<String, dynamic>?> _ping(String status) async {
    final id = _activeSessionId;
    if (id == null) return null;
    await _resolveDeviceInfoOnce();
    final localIp = await getLocalIpAddress();
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
        answers: _answers,
        elapsedSeconds: _elapsedSeconds,
        localIp: localIp,
        machineId: _cachedMachineId,
        macAddress: _cachedMacAddress,
        capabilities: _capabilities,
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
      reconcileProctorState(
        locked: response['locked'] as bool?,
        extraTimeSeconds: response['extra_time_seconds'] as int?,
        commands: response['commands'] as List<dynamic>?,
      );
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
