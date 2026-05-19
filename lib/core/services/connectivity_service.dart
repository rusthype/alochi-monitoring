// lib/core/services/connectivity_service.dart
//
// Windows uchun ishonchli internet tekshiruvi.
// connectivity_plus paketi Windows da ishonchsiz — o'zimiz tekshiramiz.

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class ConnectivityService {
  ConnectivityService._();
  static final ConnectivityService instance = ConnectivityService._();

  bool _isOnline = false;
  bool get isOnline => _isOnline;

  final _controller = StreamController<bool>.broadcast();
  Stream<bool> get onChanged => _controller.stream;

  Timer? _timer;

  // Tekshiriladigan URL lar (birinchi javob berganiga ishoniladi)
  static const _checkUrls = [
    'https://api.alochi.org/api/v1/monitoring/pack/version/',
    'https://www.google.com',
    'https://www.cloudflare.com',
  ];

  /// Fon tekshiruvini boshlash (30 soniyada bir marta)
  void startMonitoring() {
    _timer?.cancel();
    _checkNow();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _checkNow());
  }

  void stopMonitoring() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _checkNow() async {
    final online = await check();
    if (online != _isOnline) {
      _isOnline = online;
      _controller.add(online);
      debugPrint('[Connectivity] Changed → ${online ? "ONLINE" : "OFFLINE"}');
    }
  }

  /// Bir martalik tekshiruv
  static Future<bool> check({Duration timeout = const Duration(seconds: 5)}) async {
    for (final url in _checkUrls) {
      try {
        final resp = await http.get(Uri.parse(url))
            .timeout(timeout);
        if (resp.statusCode < 500) return true;
      } catch (_) {
        continue;
      }
    }
    return false;
  }

  void dispose() {
    _timer?.cancel();
    _controller.close();
  }
}
