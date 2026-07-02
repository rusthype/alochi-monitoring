// lib/main.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/sync/sync_service.dart';
import 'core/services/heartbeat_service.dart';
import 'shared/theme/app_theme.dart';
import 'features/auth/login_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      debugPrint('Flutter error: ${details.exceptionAsString()}');
      FlutterError.presentError(details);
    };

    try {
      runApp(const AlochiMonitoringApp());
      if (!kIsWeb) {
          SyncService.instance.start();
          unawaited(HeartbeatService.instance.start());
        }
    } catch (error, stackTrace) {
      debugPrint('Startup error: $error');
      debugPrint('$stackTrace');
    }
  }, (error, stackTrace) {
    debugPrint('Uncaught app error: $error');
    debugPrint('$stackTrace');
  });
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
