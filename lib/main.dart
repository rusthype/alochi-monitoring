// lib/main.dart
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'core/sync/sync_service.dart';
import 'shared/theme/app_theme.dart';
import 'features/auth/login_screen.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    if (!kIsWeb && (Platform.isWindows || Platform.isMacOS)) {
      HttpOverrides.global = _DesktopHttpOverrides();
    }

    FlutterError.onError = (details) {
      debugPrint('Flutter error: ${details.exceptionAsString()}');
      FlutterError.presentError(details);
    };

    try {
      runApp(const AlochiMonitoringApp());
      SyncService.instance.start();
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

class _DesktopHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}
