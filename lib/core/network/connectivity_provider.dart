// lib/core/network/connectivity_provider.dart
//
// Riverpod exposure of ConnectivityService, mirroring the codegen-free
// NotifierProvider pattern used by lib/core/locale/locale_provider.dart.
import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connectivity_service.dart';

final signalProvider = NotifierProvider<SignalNotifier, SignalReading>(() {
  return SignalNotifier();
});

class SignalNotifier extends Notifier<SignalReading> {
  StreamSubscription<SignalReading>? _sub;

  @override
  SignalReading build() {
    ConnectivityService.instance.start();
    _sub = ConnectivityService.instance.readings.listen((reading) {
      state = reading;
    });
    ref.onDispose(() {
      _sub?.cancel();
      ConnectivityService.instance.dispose();
    });
    return ConnectivityService.instance.last;
  }

  Future<void> refresh() => ConnectivityService.instance.refresh();
}
