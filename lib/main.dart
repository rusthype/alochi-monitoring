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
      // Explicit ProviderContainer (instead of a bare ProviderScope) so that
      // main() — which runs outside the widget tree — can read the SAME
      // goRouterProvider instance the widget tree uses, to reuse its
      // NavigatorState for the "Check for Updates..." menu dialog below.
      // UncontrolledProviderScope wires this container into the app exactly
      // like ProviderScope would.
      final container = ProviderContainer(
        overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
      );
      runApp(
        UncontrolledProviderScope(
          container: container,
          child: const AlochiMonitoringApp(),
        ),
      );
      if (!kIsWeb) {
        SyncService.instance.start();
        unawaited(HeartbeatService.instance.start());

        if (Platform.isMacOS) {
          try {
            // Try each candidate menu title in order, but stop at the first
            // one that actually exists: MacMenuBar.addMenuItem's native side
            // matches menus by exact title and returns false (no exception)
            // when no menu with that title exists — it does not throw and
            // does not create a menu. Without capturing the bool and
            // breaking, every candidate that DOES match (e.g. both the real
            // app menu 'alochi_monitoring' and Cocoa's default 'Help' menu)
            // gets the item added, duplicating "Check for Updates..." in two
            // places in the menu bar.
            for (final mId in [
              'alochi_monitoring',
              'Alochi Monitoring',
              'APP_NAME',
              'Help'
            ]) {
              try {
                final added = await MacMenuBar.addMenuItem(
                  menuId: mId,
                  itemId: 'check_updates',
                  title: 'Check for Updates...',
                );
                if (added) break;
              } catch (e) {
                debugPrint('mac_menu_bar could not add to $mId: $e');
              }
            }
            // Reuse GoRouter's own (auto-created) navigatorKey so the menu
            // handler below — which runs outside any widget's BuildContext —
            // can show a dialog via its NavigatorState.
            final navigatorKey =
                container.read(goRouterProvider).routerDelegate.navigatorKey;
            MacMenuBar.setMenuItemSelectedHandler((itemId) async {
              if (itemId == 'check_updates') {
                final updateInfo =
                    await UpdateService.instance.fetchUpdateInfo();
                if (updateInfo != null) {
                  // Open the release page (not the raw asset URL) — it has
                  // the Gatekeeper "right-click -> Open" instructions this
                  // ad-hoc-signed build needs; a raw .dmg download here would
                  // leave the user with an unexplained "can't be opened".
                  await UpdateService.instance.openReleasePage();
                } else {
                  // Manual "Check for Updates..." is a user-initiated action;
                  // unlike the passive login-screen badge, staying silent
                  // when already up to date is indistinguishable from the
                  // menu item being broken.
                  final dialogContext = navigatorKey.currentContext;
                  if (dialogContext != null && dialogContext.mounted) {
                    showDialog<void>(
                      context: dialogContext,
                      builder: (context) => AlertDialog(
                        title: const Text('Yangilanish'),
                        content: const Text(
                          'Sizda dasturning eng so\'nggi versiyasi o\'rnatilgan.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Yaxshi'),
                          ),
                        ],
                      ),
                    );
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
