import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/utils/student_name_formatter.dart';

void main() {
  group('latinToCyrillicUzbek', () {
    test('known pair: Qo\'qon -> Қўқон', () {
      expect(latinToCyrillicUzbek("Qo'qon"), 'Қўқон');
    });

    test('mirrors the Boqiyev/BOQIYEV<->BOQIEV ye-glide test case', () {
      expect(latinToCyrillicUzbek('Boqiyev'), 'Боқиев');
    });

    test('full school name with digits/hyphen/apostrophes', () {
      expect(
        latinToCyrillicUzbek("Qo'qon shahar 41-sonli umumiy o'rta ta'lim maktabi"),
        'Қўқон шаҳар 41-сонли умумий ўрта таълим мактаби',
      );
    });

    test('no-op on already-Cyrillic input', () {
      expect(latinToCyrillicUzbek('Абдулбоқиев'), 'Абдулбоқиев');
    });

    test('round-trip: cyrillicToLatinUzbek then latinToCyrillicUzbek', () {
      const original = 'БОҚИЕВ';
      final latin = cyrillicToLatinUzbek(original);
      expect(latinToCyrillicUzbek(latin), original);
    });
  });

  group('toDisplayScript', () {
    const ru = Locale('ru');
    const uz = Locale('uz');

    test('ru locale converts Latin school name to Cyrillic', () {
      expect(
        toDisplayScript('88 maktab', ru),
        '88 мактаб',
      );
    });

    test('ru locale converts formatted student name to Cyrillic', () {
      expect(
        toDisplayScript('Abdulazizov Abduxoliq', ru),
        'Абдулазизов Абдухолиқ',
      );
    });

    test('ru locale leaves already-Cyrillic text untouched', () {
      expect(toDisplayScript('Каримова Мадина', ru), 'Каримова Мадина');
    });

    test('uz locale converts Cyrillic to Latin', () {
      expect(toDisplayScript('Каримова', uz), 'Karimova');
    });

    test('uz locale leaves already-Latin text untouched', () {
      expect(toDisplayScript('Karimova', uz), 'Karimova');
    });
  });

  group('formatStudentDisplayName', () {
    test('drops Latin o\'g\'li patronymic marker', () {
      expect(
        formatStudentDisplayName("ABDUJABBOROV BEGZODBEK DILSHOD O'G'LI"),
        "Abdujabborov Begzodbek",
      );
    });

    test('transliterates Cyrillic and drops ЎҒЛИ marker', () {
      expect(
        formatStudentDisplayName("АБДУЛБОҚИЕВ ДИЛШОДБЕК ОЛИМЖОН ЎҒЛИ"),
        "Abdulboqiyev Dilshodbek",
      );
    });

    test('drops -OVICH patronymic suffix', () {
      expect(
        formatStudentDisplayName("KOBILOV JASUR ANVAROVICH"),
        "Kobilov Jasur",
      );
    });

    test('drops Cyrillic qizi marker and transliterates', () {
      expect(
        formatStudentDisplayName("Каримова Мадина Акмал кизи"),
        "Karimova Madina",
      );
    });

    test('single-token name passes through Title Cased', () {
      expect(formatStudentDisplayName("ALISHER"), "Alisher");
    });

    test('Cyrillic tutuq belgisi (ъ) maps to an apostrophe, not empty', () {
      expect(formatStudentDisplayName("Раъно"), "Ra'no");
    });
  });
}
