// lib/main.dart
import 'package:flutter/material.dart';
import 'core/api/api_client.dart';
import 'core/db/offline_queue.dart';
import 'shared/theme/app_theme.dart';
import 'features/auth/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Offline navbatdagi natijalarni yuborishga urinish
  _tryFlushQueue();

  runApp(const AlochiMonitoringApp());
}

Future<void> _tryFlushQueue() async {
  try {
    final pending = await OfflineQueue.pendingCount();
    if (pending > 0) {
      await OfflineQueue.flush(api.submitResult);
    }
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
      home: const LoginScreen(),
    );
  }
}
