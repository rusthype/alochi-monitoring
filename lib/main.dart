// lib/main.dart
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'core/sync/sync_service.dart';
import 'core/services/heartbeat_service.dart';
import 'core/network/connectivity_service.dart';
import 'core/locale/locale_provider.dart';
import 'core/theme/app_prefs_provider.dart';
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
  // Defense-in-depth: Flutter's default ErrorWidget.builder renders an
  // essentially blank, textless box in release builds (the message is
  // stripped via `assert()`), which — with no Directionality/Theme/MediaQuery
  // ancestor available if the crash happens on the very first frame — reads
  // to a real user as an unexplained solid gray fill with no login screen,
  // no error, no spinner. That exact failure mode shipped in v1.0.58 (a
  // `AppLocalizations.of(context)!` null-check thrown from
  // AlochiMonitoringApp.build(), fixed below). Overriding the builder here
  // guarantees ANY future build-time exception, anywhere in the tree, is
  // shown to the user instead of silently rendering nothing.
  ErrorWidget.builder = (FlutterErrorDetails details) {
    debugPrint('ErrorWidget: ${details.exceptionAsString()}');
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Material(
        color: const Color(0xFF1B1B1F),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Text(
              'Xatolik yuz berdi: ${details.exceptionAsString()}',
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  };

  runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // Dart/BoringSSL ships its own static root CA bundle (frozen at the SDK
    // version this build was compiled with) instead of reading the OS trust
    // store — so a server-side CA chain rollover (e.g. a new Let's Encrypt
    // cross-sign intermediate) that every browser already trusts can still
    // fail here with CERTIFICATE_VERIFY_FAILED / "unable to get local issuer
    // certificate" on Windows clients. Explicitly trusting the current ISRG
    // roots closes that gap without disabling verification.
    if (!kIsWeb) {
      try {
        for (final asset in [
          'assets/certs/isrg_root_x1.pem',
          'assets/certs/isrg_root_x2.pem',
        ]) {
          final bytes = (await rootBundle.load(asset)).buffer.asUint8List();
          SecurityContext.defaultContext.setTrustedCertificatesBytes(bytes);
        }
      } catch (error) {
        debugPrint('Trusted root CA bundle load failed: $error');
      }
    }

    FlutterError.onError = (details) {
      debugPrint('Flutter error: ${details.exceptionAsString()}');
      FlutterError.presentError(details);
    };

    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
    } catch (error, stackTrace) {
      // Non-essential for reaching a visible UI: locale/prefs-backed
      // providers fall back to their defaults below rather than blocking
      // runApp() entirely. Previously, a throw here meant runApp() was
      // NEVER called — not even a gray box, a genuinely blank native window.
      debugPrint('SharedPreferences init failed: $error');
      debugPrint('$stackTrace');
    }

    try {
      // Explicit ProviderContainer (instead of a bare ProviderScope) so that
      // main() — which runs outside the widget tree — can read the SAME
      // goRouterProvider instance the widget tree uses, to reuse its
      // NavigatorState for the "Check for Updates..." menu dialog below.
      // UncontrolledProviderScope wires this container into the app exactly
      // like ProviderScope would.
      final container = ProviderContainer(
        overrides: [
          if (prefs != null) sharedPreferencesProvider.overrideWithValue(prefs),
        ],
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
        ConnectivityService.instance.start();

        if (Platform.isMacOS) {
          try {
            // main() runs outside the widget tree, so there's no
            // BuildContext to call AppLocalizations.of(context) with here —
            // load the localizations bundle directly from the currently
            // selected locale instead.
            final menuL10n = await AppLocalizations.delegate
                .load(container.read(localeProvider));
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
                  title: menuL10n.checkForUpdates,
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
                        title: Text(AppLocalizations.of(context)!.updateBtn),
                        content: Text(
                          AppLocalizations.of(context)!.updateUpToDateMessage,
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: Text(AppLocalizations.of(context)!.okBtn),
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
    final themeMode = ref.watch(themeModeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    return InactivityWrapper(
      child: MaterialApp.router(
        // ROOT CAUSE of the v1.0.58/v1.0.59 "solid gray screen on launch"
        // bug: `title` is evaluated in AlochiMonitoringApp.build() — i.e.
        // using the context ABOVE MaterialApp.router in the tree, before
        // MaterialApp has created its own Localizations ancestor. Calling
        // AppLocalizations.of(context) there always returns null (no
        // Localizations ancestor exists yet), so the `!` threw
        // "Null check operator used on a null value" on literally every
        // launch — before login screen, before routing, before anything.
        // Flutter caught the build() exception and substituted its default
        // ErrorWidget, which in release mode renders as a textless
        // near-black/gray box (message text is stripped via `assert()`),
        // exactly matching the reported symptom. Fix: use `onGenerateTitle`,
        // which MaterialApp invokes from a Builder that IS a descendant of
        // the Localizations it establishes — the framework-sanctioned way
        // to localize the OS-level window/task-switcher title. `title`
        // stays as a static fallback (used only if onGenerateTitle is ever
        // null; here it's always ignored in favor of onGenerateTitle once
        // set, per MaterialApp's own docs).
        title: 'Alochi Monitoring',
        onGenerateTitle: (context) =>
            AppLocalizations.of(context)!.appNameTitle,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.theme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        routerConfig: router,
        builder: (context, child) {
          return MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(fontScale)),
            child: Shortcuts(
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
