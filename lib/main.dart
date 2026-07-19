// lib/main.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/sync/sync_service.dart';
import 'core/services/heartbeat_service.dart';
import 'core/locale/locale_provider.dart';
import 'l10n/app_localizations.dart';
import 'shared/theme/app_theme.dart';
import 'core/router/app_router.dart';
import 'core/widgets/inactivity_wrapper.dart';
import 'core/widgets/command_palette.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:mac_menu_bar/mac_menu_bar.dart';
import 'package:url_launcher/url_launcher.dart';
import 'core/services/update_service.dart';

void main() {
  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    FlutterError.onError = (details) {
      debugPrint('Flutter error: ${details.exceptionAsString()}');
      FlutterError.presentError(details);
    };

    try {
      final prefs = await SharedPreferences.getInstance();
      runApp(
        ProviderScope(
          overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
          child: const AlochiMonitoringApp(),
        ),
      );
      if (!kIsWeb) {
        SyncService.instance.start();
        unawaited(HeartbeatService.instance.start());

        if (Platform.isMacOS) {
          try {
            for (final mId in [
              'alochi_monitoring',
              'Alochi Monitoring',
              'APP_NAME',
              'Help'
            ]) {
              try {
                await MacMenuBar.addMenuItem(
                  menuId: mId,
                  itemId: 'check_updates',
                  title: 'Check for Updates...',
                );
              } catch (e) {
                debugPrint('mac_menu_bar could not add to $mId: $e');
              }
            }
            MacMenuBar.setMenuItemSelectedHandler((itemId) async {
              if (itemId == 'check_updates') {
                final updateInfo =
                    await UpdateService.instance.fetchUpdateInfo();
                if (updateInfo != null) {
                  final url = Uri.parse(updateInfo.downloadUrl);
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url);
                  }
                }
              }
            });
          } catch (e) {
            debugPrint('mac_menu_bar error: $e');
          }
        }
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

class AlochiMonitoringApp extends ConsumerWidget {
  const AlochiMonitoringApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final router = ref.watch(goRouterProvider);
    return InactivityWrapper(
      child: MaterialApp.router(
        title: 'Alochi Monitoring',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) {
          return Shortcuts(
            shortcuts: <ShortcutActivator, Intent>{
              LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK):
                  const CommandPaletteIntent(),
              LogicalKeySet(
                      LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
                  const CommandPaletteIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                CommandPaletteIntent: CallbackAction<CommandPaletteIntent>(
                  onInvoke: (CommandPaletteIntent intent) {
                    CommandPalette.show(context);
                    return null;
                  },
                ),
              },
              child: child!,
            ),
          );
        },
      ),
    );
  }
}

class CommandPaletteIntent extends Intent {
  const CommandPaletteIntent();
}
