// lib/core/sync/sync_service.dart
// Oflayn navbatlarni internet paydo bo'lganda avtomatik yuboruvchi xizmat.
import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../db/offline_queue.dart';

class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  StreamSubscription<List<ConnectivityResult>>? _connSub;
  Timer? _timer;
  bool _flushing = false;
  bool _started = false;
  static const Duration _interval = Duration(seconds: 60);

  void start() {
    if (_started) return;
    _started = true;
    _connSub = Connectivity().onConnectivityChanged.listen((results) {
      if (_hasNetwork(results)) _flushAll();
    });
    _timer = Timer.periodic(_interval, (_) => _flushAll());
    _flushAll();
  }

  bool _hasNetwork(List<ConnectivityResult> results) {
    if (results.isEmpty) return false;
    return results.any((r) => r != ConnectivityResult.none);
  }

  Future<void> _flushAll() async {
    if (_flushing) return;
    _flushing = true;
    try {
      final pendingOnline = await OfflineQueue.pendingCount();
      if (pendingOnline > 0) await OfflineQueue.flush(api.submitResult);
      final pendingLocal = await OfflineQueue.pendingLocalCount();
      if (pendingLocal > 0) await OfflineQueue.flushLocal(api.submitLocalResult);
    } catch (e) {
      debugPrint('SyncService._flushAll error: $e');
    } finally {
      _flushing = false;
    }
  }

  void dispose() {
    _connSub?.cancel(); _connSub = null;
    _timer?.cancel(); _timer = null;
    _started = false;
  }
}
