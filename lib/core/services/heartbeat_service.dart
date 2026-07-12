// lib/core/services/heartbeat_service.dart
import 'dart:async';
import 'package:flutter/widgets.dart';
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
  String? _sessionId;
  String _schoolCode = '';
  String _name = '';
  String _variant = '';
  String _testKey = '';
  String? _studentCode;
  int _tabSwitchCount = 0;
  int? _currentQuestionIndex;
  int? _totalQuestions;
  List<int>? _questionTimes;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(_prefsKey);
    if (id == null || id.isEmpty) {
      id = const Uuid().v4();
      await prefs.setString(_prefsKey, id);
    }
    _sessionId = id;
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
    _schoolCode = schoolCode;
    _name = name;
    _variant = variant;
    _testKey = testKey;
    _studentCode = studentCode;
    _tabSwitchCount = 0;
    unawaited(_ping('active'));
  }

  void finishTest() {
    _schoolCode = '';
    _name = '';
    _variant = '';
    _testKey = '';
    _studentCode = null;
    _tabSwitchCount = 0;
    _currentQuestionIndex = null;
    _totalQuestions = null;
    _questionTimes = null;
    unawaited(_ping('active'));
  }

  void updateProgress(
      int currentQuestionIndex, int totalQuestions, List<int> questionTimes) {
    _currentQuestionIndex = currentQuestionIndex;
    _totalQuestions = totalQuestions;
    _questionTimes = questionTimes;
  }

  Future<void> _ping(String status) async {
    final id = _sessionId;
    if (id == null) return;
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
