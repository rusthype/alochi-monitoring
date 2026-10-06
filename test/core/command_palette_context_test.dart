import 'package:alochi_monitoring/core/widgets/command_palette.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

class _PaletteIntent extends Intent {
  const _PaletteIntent();
}

/// Mirrors lib/main.dart: Shortcuts/Actions live in `MaterialApp.router`'s
/// `builder`, whose context is ABOVE the Router/Navigator.
/// [useRouterContext] = true is the production code path
/// (`CommandPalette.showFromRouter`); false is the old buggy path
/// (`CommandPalette.show(builderContext)`).
Future<void> _pump(
  WidgetTester tester, {
  required bool useRouterContext,
}) async {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => const Scaffold(
          body: Center(child: TextField(autofocus: true)),
        ),
      ),
    ],
  );
  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => Shortcuts(
        shortcuts: <ShortcutActivator, Intent>{
          LogicalKeySet(LogicalKeyboardKey.meta, LogicalKeyboardKey.keyK):
              const _PaletteIntent(),
          LogicalKeySet(LogicalKeyboardKey.control, LogicalKeyboardKey.keyK):
              const _PaletteIntent(),
        },
        child: Actions(
          actions: <Type, Action<Intent>>{
            _PaletteIntent: CallbackAction<_PaletteIntent>(
              onInvoke: (_) {
                if (useRouterContext) {
                  CommandPalette.showFromRouter(router);
                } else {
                  CommandPalette.show(context);
                }
                return null;
              },
            ),
          },
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _chord(WidgetTester tester, LogicalKeyboardKey mod) async {
  await tester.sendKeyDownEvent(mod);
  await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
  await tester.sendKeyUpEvent(mod);
  await tester.pumpAndSettle();
}

void main() {
  for (final entry in {
    'Ctrl+K': LogicalKeyboardKey.control,
    'Cmd+K': LogicalKeyboardKey.meta,
  }.entries) {
    testWidgets('${entry.key} opens CommandPalette without exception',
        (tester) async {
      await _pump(tester, useRouterContext: true);
      await _chord(tester, entry.value);
      expect(tester.takeException(), isNull);
      expect(find.byType(CommandPalette), findsOneWidget);
    });
  }

  testWidgets('regression doc: builder context has no Navigator (old bug)',
      (tester) async {
    await _pump(tester, useRouterContext: false);
    await _chord(tester, LogicalKeyboardKey.control);
    expect(tester.takeException(), isNotNull);
    expect(find.byType(CommandPalette), findsNothing);
  });
}
