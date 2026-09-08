import 'package:flutter_test/flutter_test.dart';
import 'package:alochi_monitoring/core/utils/student_name_formatter.dart';

void main() {
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
