// lib/core/diagnostics/device_command_client.dart
//
// Receives remote commands from the admin panel over an anonymous WebSocket
// (`/ws/kiosk/device/?device_id=<id>`). Only one command exists: `force_update`.
// The socket carries NO url or payload that influences what is installed: the
// update itself always goes through UpdateService (hardcoded manifest URLs).
// A spoofed message can at most make this device check for / install the
// already-published release earlier. Never throws into the UI.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../network/connectivity_service.dart';
import '../offline/lan_client_session.dart' show isOfflineModeOpen;
import '../services/update_service.dart';
import 'active_test_gate.dart';
import 'device_info_collector.dart';
import 'error_log.dart';
import 'kiosk_command_auth.dart';

/// Minimal socket surface so tests can inject a fake.
abstract class CommandChannel {
  Stream<dynamic> get stream;
  void add(String message);
  Future<void> close();
}

typedef CommandChannelFactory = Future<CommandChannel> Function(Uri uri);

class _IoCommandChannel implements CommandChannel {
  _IoCommandChannel(this._ws);
  final WebSocket _ws;
  @override
  Stream<dynamic> get stream => _ws;
  @override
  void add(String message) => _ws.add(message);
  @override
  Future<void> close() => _ws.close();
}

Future<CommandChannel> _connectIo(Uri uri) async {
  final ws = await WebSocket.connect(uri.toString())
      .timeout(const Duration(seconds: 15));
  ws.pingInterval = const Duration(seconds: 30);
  return _IoCommandChannel(ws);
}

const kPendingForceUpdateKey = 'pending_force_update_request_id';
const kSeenCommandIdsKey = 'kiosk_cmd_seen_ids';
const _seenCap = 20;

class DeviceCommandClient {
  DeviceCommandClient({
    CommandChannelFactory? connect,
    Future<void> Function(Duration)? sleep,
    double Function()? random,
    DateTime Function()? now,
    Future<String> Function()? deviceId,
    bool Function()? shouldConnect,
    ValueListenable<bool>? testGate,
    Future<UpdateInfo?> Function()? checkUpdate,
    Future<UpdateResult> Function(UpdateInfo)? installUpdate,
    Uint8List? commandPublicKey,
    Ed25519Verify? verifySignature,
    this.apiBase = _defaultHost,
    this.deferredGrace = const Duration(seconds: 15),
  })  : _connect = connect ?? _connectIo,
        _sleep = sleep ?? Future<void>.delayed,
        _random = random ?? Random().nextDouble,
        _now = now ?? DateTime.now,
        _deviceId = deviceId ?? DeviceInfoCollector.deviceId,
        _pubKey = commandPublicKey ?? kioskCommandPublicKeyFromEnvironment(),
        _verify = verifySignature ?? unavailableEd25519Verify,
        _shouldConnect = shouldConnect ?? _defaultShouldConnect,
        _gate = testGate ?? ActiveTestGate.active,
        _check = checkUpdate ?? UpdateService.instance.fetchUpdateInfo,
        _install =
            installUpdate ?? UpdateService.instance.downloadAndInstallUpdate;

  static const String _defaultHost = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.alochi.org',
  );

  static final instance = DeviceCommandClient();

  /// Not in offline-pack / LAN-client mode, and not while the connectivity
  /// probe says the backend is unreachable (a first probe still pending counts
  /// as reachable).
  static bool _defaultShouldConnect() {
    if (isOfflineModeOpen) return false;
    final r = ConnectivityService.instance.last;
    return r.checking || r.tier != SignalTier.none;
  }

  static const Duration baseDelay = Duration(seconds: 5);
  static const Duration maxDelay = Duration(minutes: 5);
  static const Duration offlineRecheck = Duration(seconds: 30);
  // A connection that dies sooner than this does not reset the backoff.
  static const Duration minStableConnection = Duration(seconds: 10);
  static const int maxMessageChars = 4096;

  final String apiBase;
  final Duration deferredGrace;
  final CommandChannelFactory _connect;
  final Future<void> Function(Duration) _sleep;
  final double Function() _random;
  final DateTime Function() _now;
  final Future<String> Function() _deviceId;
  final Uint8List? _pubKey;
  final Ed25519Verify _verify;
  final bool Function() _shouldConnect;
  final ValueListenable<bool> _gate;
  final Future<UpdateInfo?> Function() _check;
  final Future<UpdateResult> Function(UpdateInfo) _install;

  bool _started = false;
  bool _stopped = false;
  CommandChannel? _channel;
  final List<String> _seen = [];
  String? _pendingId; // deferred force_update waiting for the gate
  bool _updating = false;

  /// http->ws, https->wss on the API host. Null if [base] is not usable.
  static Uri? buildUri(String base, String deviceId) {
    final b = Uri.tryParse(base);
    if (b == null || b.host.isEmpty || deviceId.isEmpty) return null;
    return Uri(
      scheme: b.scheme == 'https' ? 'wss' : 'ws',
      host: b.host,
      port: b.hasPort ? b.port : null,
      path: '/ws/kiosk/device/',
      queryParameters: {'device_id': deviceId},
    );
  }

  /// Delay before reconnect attempt number [attempt] (0-based): 5s doubling to
  /// the 5 min cap, minus up to 20% jitter (never exceeds the cap).
  Duration backoff(int attempt) {
    final ms = min(maxDelay.inMilliseconds,
        baseDelay.inMilliseconds * (1 << min(attempt, 20)));
    return Duration(milliseconds: (ms * (1 - 0.2 * _random())).round());
  }

  /// Call once from main(); returns immediately.
  void start() {
    if (_started) return;
    _started = true;
    _gate.addListener(_onGate);
    unawaited(_restorePending());
    unawaited(_run());
  }

  @visibleForTesting
  Future<void> stop() async {
    _stopped = true;
    _gate.removeListener(_onGate);
    final c = _channel;
    _channel = null;
    try {
      await c?.close();
    } catch (_) {}
  }

  Future<void> _run() async {
    var attempt = 0;
    while (!_stopped) {
      try {
        if (!_shouldConnect()) {
          await _sleep(offlineRecheck);
          continue;
        }
        final id = await _deviceId();
        final uri = buildUri(apiBase, id);
        if (uri == null) {
          await _sleep(backoff(attempt++));
          continue;
        }
        final CommandChannel ch;
        try {
          ch = await _connect(uri);
        } on WebSocketException catch (e) {
          // Handshake rejected (404/403: backend without the endpoint, or
          // not upgraded): stay quiet and go straight to the cap.
          debugPrint('DeviceCommandClient handshake: ${e.runtimeType}');
          attempt = 20;
          await _sleep(backoff(attempt));
          continue;
        }
        if (_stopped) {
          await ch.close();
          return;
        }
        _channel = ch;
        final since = _now();
        try {
          await for (final m in ch.stream) {
            _onMessage(m);
          }
        } finally {
          if (identical(_channel, ch)) _channel = null;
        }
        if (_now().difference(since) >= minStableConnection) attempt = 0;
      } catch (e) {
        debugPrint('DeviceCommandClient: ${e.runtimeType}');
      }
      if (_stopped) return;
      await _sleep(backoff(attempt++));
    }
  }

  void _send(Map<String, dynamic> msg) {
    try {
      final s = jsonEncode(msg);
      if (s.length <= 1024) _channel?.add(s);
    } catch (e) {
      debugPrint('DeviceCommandClient send: ${e.runtimeType}');
    }
  }

  void _ack(String requestId, String status) =>
      _send({'type': 'ack', 'request_id': requestId, 'status': status});

  static final _idRe = RegExp(r'^[A-Za-z0-9_.:\-]{1,64}$');

  void _onMessage(dynamic raw) => unawaited(_accept(raw));

  Future<void> _accept(dynamic raw) async {
    try {
      if (raw is! String || raw.length > maxMessageChars) return;
      final m = jsonDecode(raw);
      if (m is! Map) return;
      if (m['type'] != 'command' || m['command'] != 'force_update') return;
      final id = m['request_id'];
      if (id is! String || !_idRe.hasMatch(id)) return;
      final reason = checkCommandAuth(
        m,
        publicKey: _pubKey,
        ownDeviceId: await _deviceId(),
        now: _now(),
        verify: _verify,
      );
      if (reason != null) {
        debugPrint('DeviceCommandClient reject: $reason');
        return;
      }
      await _loadSeen();
      if (_seen.contains(id)) return;
      _seen.add(id); // no await between the check above and this add
      if (_seen.length > _seenCap) _seen.removeAt(0);
      await _saveSeen();
      unawaited(_handleForceUpdate(id));
    } catch (e) {
      debugPrint('DeviceCommandClient parse: ${e.runtimeType}');
    }
  }

  Future<void>? _seenLoad;

  Future<void> _loadSeen() => _seenLoad ??= _doLoadSeen();

  Future<void> _doLoadSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      final l = jsonDecode(p.getString(kSeenCommandIdsKey) ?? '[]') as List;
      for (final e in l) {
        if (e is String && !_seen.contains(e)) _seen.add(e);
      }
    } catch (e) {
      debugPrint('DeviceCommandClient seen: ${e.runtimeType}');
    }
  }

  Future<void> _saveSeen() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString(kSeenCommandIdsKey, jsonEncode(_seen));
    } catch (e) {
      debugPrint('DeviceCommandClient seen: ${e.runtimeType}');
    }
  }

  Future<void> _handleForceUpdate(String id) async {
    try {
      if (_updating) return _ack(id, 'updating');
      if (_pendingId != null) {
        // Latest request wins; still waiting for the test to end.
        await _setPending(id);
        return _ack(id, 'deferred');
      }
      final info = await _check();
      if (info == null) return _ack(id, 'up_to_date');
      if (_gate.value) {
        await _setPending(id);
        return _ack(id, 'deferred');
      }
      await _beginUpdate(id, info);
    } catch (e) {
      debugPrint('DeviceCommandClient command: ${e.runtimeType}');
      _ack(id, 'failed');
    }
  }

  Future<void> _beginUpdate(String id, UpdateInfo info) async {
    _updating = true;
    await _setPending(null);
    // Ack BEFORE the install: the macOS updater exits the app.
    _ack(id, 'updating');
    try {
      final r = await _install(info);
      if (!r.success) _ack(id, 'failed'); // UpdateService already ErrorLog'd it
    } catch (e) {
      unawaited(ErrorLog.record(e, 'update:force_update'));
      _ack(id, 'failed');
    } finally {
      _updating = false;
    }
  }

  void _onGate() {
    if (!_gate.value && _pendingId != null) unawaited(_runDeferred());
  }

  Future<void> _runDeferred() async {
    try {
      // Let the finished attempt's result submission settle first.
      await _sleep(deferredGrace);
      final id = _pendingId;
      if (id == null || _gate.value || _updating || _stopped) return;
      final info = await _check();
      if (info == null) {
        await _setPending(null);
        return _ack(id, 'up_to_date');
      }
      if (_gate.value) return; // a new test started meanwhile; wait again
      await _beginUpdate(id, info);
    } catch (e) {
      debugPrint('DeviceCommandClient deferred: ${e.runtimeType}');
    }
  }

  Future<void> _setPending(String? id) async {
    _pendingId = id;
    try {
      final p = await SharedPreferences.getInstance();
      if (id == null) {
        await p.remove(kPendingForceUpdateKey);
      } else {
        await p.setString(kPendingForceUpdateKey, id);
      }
    } catch (e) {
      debugPrint('DeviceCommandClient prefs: ${e.runtimeType}');
    }
  }

  /// App restarted while a command was deferred: honour it once idle.
  Future<void> _restorePending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = prefs.getString(kPendingForceUpdateKey);
      if (id == null || !_idRe.hasMatch(id)) return;
      _pendingId = id;
      if (!_gate.value) unawaited(_runDeferred());
    } catch (e) {
      debugPrint('DeviceCommandClient restore: ${e.runtimeType}');
    }
  }
}
