import 'package:alochi_monitoring/core/locale/locale_provider.dart';
import 'package:alochi_monitoring/features/diagnostic/data/diagnostic_school_list.dart';
import 'package:alochi_monitoring/features/diagnostic/screens/diagnostic_school_select_screen.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> row(String id, String name, Object? n,
        {String? city, String? abbr}) =>
    {
      'school_id': id,
      'school_name': name,
      'school_number': n,
      'kiosk_pin': '',
      if (city != null) 'city_name': city,
      if (abbr != null) 'abbreviation': abbr,
    };

String numLabel(int n) => '$n-maktab';

void main() {
  group('pure helpers', () {
    test('sorts numerically, null last, then by name', () {
      final out = sortSchools([
        row('a', 'Zeta', null),
        row('b', 'X', 100),
        row('c', 'Y', 9),
        row('d', 'Alpha', null),
        row('e', 'W', 26),
      ].map(DiagnosticSchool.fromMap));
      expect(out.map((s) => s.id).toList(), ['c', 'e', 'b', 'd', 'a']);
    });

    test('string school_number (offline row) parses', () {
      expect(DiagnosticSchool.fromMap(row('a', '26', '26')).number, 26);
    });

    test('strips boilerplate, falls back to full name when empty', () {
      expect(stripSchoolBoilerplate("Toshkent umumiy o'rta ta'lim maktabi"),
          'Toshkent');
      expect(
          stripSchoolBoilerplate(
              'Тошкент умумий ўрта таълим мактаби ҚА хузуридаги ихтисослаштирилган мактаб-интернат'),
          'Toshkent');
      expect(stripSchoolBoilerplate("Umumiy o'rta ta'lim maktabi"),
          "Umumiy o'rta ta'lim maktabi");
    });

    test('short name: abbreviation > number template > stripped name', () {
      const uz = Locale('uz');
      expect(
          shortSchoolName(
              DiagnosticSchool.fromMap(row('a', 'N', 5, abbr: 'IM')),
              uz,
              numLabel),
          'IM');
      expect(
          shortSchoolName(
              DiagnosticSchool.fromMap(row('a', 'N', 5)), uz, numLabel),
          '5-maktab');
      expect(
          shortSchoolName(
              DiagnosticSchool.fromMap(
                  row('a', "Chilonzor umumiy o'rta ta'lim maktabi", null)),
              uz,
              numLabel),
          'Chilonzor');
    });

    test('search matches number and name in Cyrillic and Latin', () {
      final s = DiagnosticSchool.fromMap(row('a', 'Тошкент мактаби', 26));
      expect(schoolMatchesQuery(s, '26'), isTrue);
      expect(schoolMatchesQuery(s, 'toshkent'), isTrue);
      expect(schoolMatchesQuery(s, 'Тошкент'), isTrue);
      expect(schoolMatchesQuery(s, 'samarqand'), isFalse);
      final lat = DiagnosticSchool.fromMap(row('b', 'Toshkent maktabi', 3));
      expect(schoolMatchesQuery(lat, 'тошкент'), isTrue);
    });
  });

  group('derived number', () {
    int? d(String name, [Object? n]) =>
        DiagnosticSchool.fromMap(row('a', name, n)).number;
    test('from name', () {
      expect(d("Qo'qon shahar 16-sonli umumiy o'rta ta'lim maktabi"), 16);
      expect(d('Қўқон шаҳар 16-сонли умумий ўрта таълим мактаби'), 16);
      expect(d("Buvayda tumani 5-sonli umumiy o'rta ta'lim maktabi"), 5);
      expect(d('Maktab 56'), 56);
      expect(d('88 maktab'), 88);
      expect(d('Школа №56'), 56);
      expect(d('7-школа'), 7);
    });
    test('real school_number wins; unparsable/4-digit -> null', () {
      expect(d('Maktab 56', 3), 3);
      expect(d('Toshkent maktabi'), isNull);
      expect(d('2024 maktab'), isNull);
      expect(d(''), isNull);
    });
    test('numeric ordering and search by derived number', () {
      final names = {
        '1': 'Maktab 1',
        '16': '16-sonli maktab',
        '2': '2-sonli maktab',
        '21': '21 maktab',
        '37': 'Maktab 37',
        '4': '4-sonli maktab',
        '41': '41 maktab',
        '6': '6-sonli maktab',
        '8': '8-sonli maktab',
      };
      final out = sortSchools(names.entries
          .map((e) => DiagnosticSchool.fromMap(row(e.key, e.value, null))));
      expect(
          out.map((s) => s.number).toList(), [1, 2, 4, 6, 8, 16, 21, 37, 41]);
      expect(schoolMatchesQuery(out.first, '1'), isTrue);
      expect(
          shortSchoolName(DiagnosticSchool.fromMap(row('a', 'Maktab 56', null)),
              const Locale('uz'), numLabel),
          '56-maktab');
    });
  });

  group('screen', () {
    Future<void> pump(WidgetTester t, List<Map<String, dynamic>> rows,
        {Map<String, Object> prefs = const {}}) async {
      SharedPreferences.setMockInitialValues(prefs);
      final sp = await SharedPreferences.getInstance();
      t.view.physicalSize = const Size(1280, 720);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      await t.pumpWidget(ProviderScope(
        overrides: [sharedPreferencesProvider.overrideWithValue(sp)],
        child: MaterialApp(
          locale: const Locale('uz'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: DiagnosticSchoolSelectScreen(
              loadSchools: () async => (rows, false)),
        ),
      ));
      await t.pumpAndSettle();
    }

    testWidgets('city group order is stable while searching', (t) async {
      await pump(t, [
        row('1', 'Alpha 1', 1, city: 'Buxoro'),
        row('2', 'Beta 2', 2, city: 'Samarqand'),
        row('3', 'Gamma 3', 3, city: 'Samarqand'),
        row('4', 'Delta 4', 4, city: 'Buxoro'),
      ]);
      double y(String s) => t.getTopLeft(find.text(s).last).dy;
      expect(y('Buxoro'), lessThan(y('Samarqand')));
      await t.enterText(find.byType(TextField), '3');
      await t.pumpAndSettle();
      // Buxoro group has no match now; Samarqand remains. Search 'a' keeps order.
      await t.enterText(find.byType(TextField), 'a');
      await t.pumpAndSettle();
      expect(y('Buxoro'), lessThan(y('Samarqand')));
      await t.enterText(find.byType(TextField), '3');
      await t.pumpAndSettle();
      expect(find.text('3-maktab'), findsOneWidget);
      expect(find.text('1-maktab'), findsNothing);
    });

    testWidgets('two cities -> Hammasi + 2 chips, filter works', (t) async {
      await pump(t, [
        row('1', 'A', 1, city: 'Toshkent'),
        row('2', 'B', 2, city: 'Samarqand'),
        row('3', 'C', 3),
      ]);
      expect(find.text('Hammasi'), findsOneWidget);
      // Chip + group header for each city.
      expect(find.text('Toshkent'),
          findsNWidgets(2)); // chip, header (no repeated subtitle)
      expect(find.text('Boshqa'), findsOneWidget);
      expect(find.text('3-maktab'), findsOneWidget);
      await t.tap(find.text('Samarqand').first);
      await t.pumpAndSettle();
      expect(find.text('2-maktab'), findsOneWidget);
      expect(find.text('1-maktab'), findsNothing);
      expect(find.text('3-maktab'), findsNothing);
    });

    testWidgets('single city -> no chips', (t) async {
      await pump(t, [
        row('1', 'A', 1, city: 'Toshkent'),
        row('2', 'B', 2, city: 'Toshkent'),
      ]);
      expect(find.text('Hammasi'), findsNothing);
      expect(find.text('1-maktab'), findsOneWidget);
    });

    testWidgets('old response without new fields renders; search filters',
        (t) async {
      await pump(t, [row('1', 'Alpha', 7), row('2', 'Beta', 12)]);
      expect(find.text('7-maktab'), findsOneWidget);
      expect(find.text('Hammasi'), findsNothing);
      await t.enterText(find.byType(TextField), '12');
      await t.pumpAndSettle();
      expect(find.text('12-maktab'), findsOneWidget);
      expect(find.text('7-maktab'), findsNothing);
      await t.enterText(find.byType(TextField), 'zzz');
      await t.pumpAndSettle();
      expect(find.text('Hech narsa topilmadi'), findsOneWidget);
    });

    testWidgets('last chosen school is pinned first with marker', (t) async {
      await pump(t, [row('1', 'A', 1), row('2', 'B', 2), row('3', 'C', 3)],
          prefs: {'last_diag_school_id': '3'});
      expect(find.text('Oxirgi tanlangan'), findsOneWidget);
      final y3 = t.getTopLeft(find.text('3-maktab')).dy;
      final y1 = t.getTopLeft(find.text('1-maktab')).dy;
      expect(y3, lessThan(y1));
      expect(find.text('3-maktab'), findsOneWidget); // not duplicated
    });

    testWidgets('40+ schools at 1280x720 do not overflow', (t) async {
      await pump(t, [
        for (var i = 1; i <= 45; i++)
          row('$i', 'Maktab $i', i, city: i.isEven ? 'Toshkent' : 'Buxoro'),
      ]);
      expect(t.takeException(), isNull);
    });

    testWidgets('offline single row: badge+template name, no search/headers',
        (t) async {
      await pump(t, [
        {
          'school_id': 'x',
          'school_name': '26',
          'school_number': '26',
          'kiosk_pin': '',
        },
      ]);
      expect(find.text('26-maktab'), findsOneWidget);
      expect(find.text('26'), findsWidgets); // number badge
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Boshqa'), findsNothing);
      expect(find.text('Hammasi'), findsNothing);
      expect(t.takeException(), isNull);
    });

    testWidgets('single online school with city: no chips/header/search',
        (t) async {
      await pump(t, [row('1', 'A', 5, city: 'Toshkent')]);
      expect(find.text('5-maktab'), findsOneWidget);
      expect(find.text('Toshkent'), findsOneWidget); // subtitle only
      expect(find.byType(TextField), findsNothing);
      expect(find.text('Hammasi'), findsNothing);
    });

    testWidgets('40 schools without any city: flat list, no headers',
        (t) async {
      await pump(t, [for (var i = 1; i <= 40; i++) row('$i', 'M$i', i)]);
      expect(find.text('Boshqa'), findsNothing);
      expect(find.text('Hammasi'), findsNothing);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('1-maktab'), findsOneWidget);
      expect(t.takeException(), isNull);
    });
  });
}
