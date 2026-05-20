// lib/main.dart
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'core/api/api_client.dart';
import 'core/db/offline_queue.dart';
import 'shared/theme/app_theme.dart';
import 'features/onboarding/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Windows: maximized ekran
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
    await windowManager.maximize();   // To'liq ekran (taskbar ko'rinadi)
    await windowManager.show();
    await windowManager.focus();
  });

  _tryFlushQueue();
  runApp(const AlochiMonitoringApp());
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
    return MaterialApp(
      title: 'Alochi Monitoring',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.theme,
      home: const SplashScreen(),
    );
  }
}
