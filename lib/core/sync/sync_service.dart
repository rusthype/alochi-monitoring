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
  int _consecutiveFailures = 0;
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

  Future<void> flushNow() => _flushAll();

  Future<void> _flushAll() async {
    if (_flushing) return;
    _flushing = true;
    try {
      // Navbat bo'sh bo'lsa tarmoqqa umuman tegmaymiz (behuda 60s flush yo'q).
      final pending = await OfflineQueue.pendingCount() +
          await OfflineQueue.pendingLocalCount();
      if (pending == 0) return;
      // Haqiqiy internetni 1 ta arzon GET bilan tekshiramiz. Interfeys "ulangan"
      // bo'lsa-da internet yo'q bo'lsa, bu N ta 20s timeout urinishidan saqlaydi.
      if (!await api.ping()) return;
      await api.flushOfflineQueue();
      _consecutiveFailures = 0;
    } catch (e) {
      _consecutiveFailures++;
      debugPrint('SyncService._flushAll error: $e');
      if (_consecutiveFailures >= 5) {
        debugPrint(
            '⚠️ SyncService: $_consecutiveFailures consecutive flush failures — results may not be reaching the server');
      }
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
