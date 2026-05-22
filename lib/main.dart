// lib/main.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:window_manager/window_manager.dart';
import 'package:path_provider_windows/path_provider_windows.dart';
import 'package:shared_preferences_windows/shared_preferences_windows.dart';
import 'core/api/api_client.dart';
import 'core/db/offline_queue.dart';
import 'shared/theme/app_theme.dart';
import 'features/onboarding/splash_screen.dart';

/// SharedPreferences debug modeda Windows da crash qilishi mumkin.
/// try-catch bilan xavfsiz yuklaymiz.
Future<bool> _loadDarkMode() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('dark_mode') ?? false;
  } catch (_) {
    return false;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Flutter xatolarini yutib olish (oq ekranni oldini oladi)
  FlutterError.onError = (details) {
    debugPrint('FlutterError: ${details.exception}');
  };

  // Windows plugin registration — debug modeda kerak
  PathProviderWindows.registerWith();
  SharedPreferencesWindows.registerWith();

  // sqflite Windows uchun FFI init
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  // Windows oyna sozlamalari
  await windowManager.ensureInitialized();
  const windowOptions = WindowOptions(
    title: 'Alochi Monitoring',
    minimumSize: Size(900, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
  });

  // Theme — SharedPreferences xavfsiz yuklash
  final isDark = await _loadDarkMode();
  final themeNotifier = ThemeNotifier();
  themeNotifier.setMode(isDark ? ThemeMode.dark : ThemeMode.light);

  // Offline queue
  _tryFlushQueue();

  runApp(
    ChangeNotifierProvider.value(
      value: themeNotifier,
      child: const AlochiMonitoringApp(),
    ),
  );
}

Future<void> _tryFlushQueue() async {
  try {
    final pending = await OfflineQueue.pendingCount();
    if (pending > 0) await OfflineQueue.flush(api.submitResult);
  } catch (_) {}
}

class AlochiMonitoringApp extends StatelessWidget {
  const AlochiMonitoringApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeNotifier = context.watch<ThemeNotifier>();
    return MaterialApp(
      title: 'Alochi Monitoring',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      darkTheme: AppTheme.darkTheme,
      themeMode: themeNotifier.mode,
      home: const SplashScreen(),
    );
  }
}
