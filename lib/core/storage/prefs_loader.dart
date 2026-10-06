import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Loads [SharedPreferences] without ever throwing, so `main()` can ALWAYS
/// override `sharedPreferencesProvider` (an un-overridden provider throws
/// UnimplementedError on the first frame — the "Xatolik yuz berdi" screen
/// instead of login).
///
/// A corrupt/unwritable `%APPDATA%\...\shared_preferences.json` on a school PC
/// makes `getInstance()` throw. We retry once after [retryDelay]; if it still
/// fails we switch the plugin to an in-memory store (settings reset to
/// defaults for this run, nothing persisted) and report via [onFailure].
/// Because `setMockInitialValues` swaps the global store, every later direct
/// `SharedPreferences.getInstance()` caller (heartbeat, attempt store, ...)
/// gets the same working in-memory instance instead of throwing again.
Future<SharedPreferences> loadPrefsWithFallback({
  Future<SharedPreferences> Function() load = SharedPreferences.getInstance,
  Duration retryDelay = const Duration(milliseconds: 300),
  void Function(Object error, StackTrace stack)? onFailure,
}) async {
  try {
    return await load();
  } catch (error, stack) {
    debugPrint('SharedPreferences init failed (retrying): $error');
    onFailure?.call(error, stack);
  }
  await Future<void>.delayed(retryDelay);
  try {
    return await load();
  } catch (error, stack) {
    debugPrint('SharedPreferences init failed again, using in-memory: $error');
    onFailure?.call(error, stack);
  }
  // ponytail: non-persistent for this run; settings reset to defaults.
  // ignore: invalid_use_of_visible_for_testing_member
  SharedPreferences.setMockInitialValues(<String, Object>{});
  return SharedPreferences.getInstance();
}
