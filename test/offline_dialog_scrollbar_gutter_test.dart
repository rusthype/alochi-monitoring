// The dialog's scrollbar must live in its own right-hand gutter (content never
// runs under the thumb) and the header must stay fixed above the scroll area.
import 'package:alochi_monitoring/features/offline/offline_control_center_dialog.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('scrollbar gutter clears buttons; header is fixed and unclipped',
      (tester) async {
    tester.view.physicalSize = const Size(900, 480); // short -> content scrolls
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      locale: Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: Center(child: OfflineControlCenterDialog())),
    ));
    await tester.pump(const Duration(milliseconds: 50));

    final l10n = AppLocalizations.of(tester.element(find.byType(Scaffold)))!;
    // The visible card (Dialog itself also spans its inset padding).
    final dialog = tester.getRect(find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first);
    final scrollbar = tester.getRect(find.byType(Scrollbar));
    final scrollable = tester.state<ScrollableState>(find.descendant(
        of: find.byType(Scrollbar), matching: find.byType(Scrollable)));

    // Content really scrolls in this viewport, so the thumb is on screen.
    expect(scrollable.position.maxScrollExtent, greaterThan(0));
    // Scrollbar hugs the dialog's right edge (thumb in the dialog padding).
    expect(dialog.right - scrollbar.right, inInclusiveRange(0, 12));

    // Every full-width button ends well before the thumb (6px thick) + 12px.
    final buttons = find.descendant(
        of: find.byType(SingleChildScrollView),
        matching: find.byWidgetPredicate(
            (w) => w is FilledButton || w is OutlinedButton));
    expect(buttons, findsWidgets);
    for (final b in buttons.evaluate()) {
      final r = tester.getRect(find.byWidget(b.widget));
      expect(r.right, lessThanOrEqualTo(scrollbar.right - 6 - 12),
          reason: 'button must not run under the scrollbar thumb');
    }
    // The link-like first button is among them.
    expect(find.text(l10n.usbLoadPack), findsOneWidget);

    // Header: not inside the scroll view, fully visible, stays put on scroll.
    final title = find.text(l10n.usbCenterTitle);
    expect(
        find.ancestor(of: title, matching: find.byType(SingleChildScrollView)),
        findsNothing);
    final before = tester.getRect(title);
    expect(before.top, greaterThanOrEqualTo(dialog.top));
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await tester.pump();
    expect(tester.getRect(title), before);
    final close = tester.getRect(find.byIcon(Icons.close_rounded));
    expect(close.right, lessThanOrEqualTo(dialog.right));
    expect(close.top, greaterThanOrEqualTo(dialog.top));
  });
}
