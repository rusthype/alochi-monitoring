import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/core/network/connectivity_provider.dart';
import 'package:alochi_monitoring/core/network/connectivity_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// signalProvider starts the real ConnectivityService (periodic ping + DNS
/// lookup with a 2s timeout) -> pending timers / real network in tests.
class _FakeSignal extends SignalNotifier {
  @override
  SignalReading build() => SignalReading(
        tier: SignalTier.excellent,
        latencyMs: 1,
        measuredAt: DateTime(2026),
      );

  @override
  Future<void> refresh() async {}
}

/// Overrides every provider that would otherwise hit real I/O when the real
/// `AlochiMonitoringApp` is pumped. Also stubs the flutter_secure_storage
/// channel (CredentialCache.clear()).
Future<List<Override>> appTestOverrides() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null);
  return [
    sharedPreferencesProvider.overrideWithValue(prefs),
    signalProvider.overrideWith(_FakeSignal.new),
  ];
}
