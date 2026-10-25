import 'package:alochi_monitoring/features/diagnostic/widgets/diagnostic_widgets.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _cyr =
    'Тошкент шаҳри Юнусобод туманидаги 777-сонли умумий ўрта таълим мактаби '
    'ҳузуридаги ихтисослаштирилган мактаб-интернат';
const _lat = 'TOSHKENT SHAHRI YUNUSOBOD TUMANIDAGI 777-SONLI UMUMIY O\'RTA '
    'TA\'LIM MAKTABI HUZURIDAGI IHTISOSLASHTIRILGAN MAKTAB-INTERNAT';

Widget _wrap(Widget child, double width) => MaterialApp(
      locale: const Locale('uz'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  for (final width in [320.0, 800.0, 1400.0]) {
    for (final name in [_cyr, _lat]) {
      testWidgets('top bar long title w=$width', (tester) async {
        await tester.pumpWidget(_wrap(DiagnosticTopBar(title: name), width));
        expect(tester.takeException(), isNull);
        final back = tester.getRect(find.byIcon(Icons.arrow_back_rounded));
        final title = tester.getRect(find.text(name.toUpperCase()));
        expect(title.left - back.right, greaterThanOrEqualTo(8));
        expect(tester.getSize(find.byType(DiagnosticTopBar)).width,
            lessThanOrEqualTo(width));
      });

      testWidgets('pill long label wraps inside w=$width', (tester) async {
        await tester.pumpWidget(_wrap(
          Wrap(children: [
            DiagnosticPillButton(label: name, isSelected: true, onTap: () {}),
          ]),
          width,
        ));
        expect(tester.takeException(), isNull);
        final pill = tester.getRect(find.byType(DiagnosticPillButton));
        final text = tester.getRect(find.text(name));
        expect(pill.width, lessThanOrEqualTo(width));
        expect(text.right, lessThanOrEqualTo(pill.right));
        expect(text.height, greaterThan(20)); // wrapped to >1 line
      });
    }
  }
}
