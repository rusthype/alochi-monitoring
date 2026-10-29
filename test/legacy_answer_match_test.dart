// Legacy runners (Unit1 / Combined / Interhouse) share the generic engine's
// number and yes/no rules for correctness checks. Stored answers stay as the
// user produced them ("YES"/"NO", typed text); only the comparison widens.
import 'package:alochi_monitoring/core/engine/answer_normalization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sameTextAnswer', () {
    test('typical correct answers (unchanged behaviour)', () {
      expect(sameTextAnswer('cat', 'cat'), true);
      expect(sameTextAnswer('CAT', 'cat'), true);
      expect(sameTextAnswer('  cat ', 'cat'), true);
      expect(sameTextAnswer('dog', 'Dog'), true);
      expect(sameTextAnswer('New York', ' new york'), true);
    });
    test('typical wrong answers (unchanged behaviour)', () {
      expect(sameTextAnswer('cta', 'cat'), false);
      expect(sameTextAnswer('', 'cat'), false);
      expect(sameTextAnswer('cat', ''), false);
      expect(sameTextAnswer('cats', 'cat'), false);
    });
    test('numbers match by value in any common spelling', () {
      for (final g in ['3', ' 3 ', '3.0', '3,0', '3.00', '03', '+3']) {
        expect(sameTextAnswer(g, '3'), true, reason: '"$g" vs 3');
      }
      expect(sameTextAnswer('2,5', '2.5'), true);
      expect(sameTextAnswer('2.5', '2,50'), true);
      expect(sameTextAnswer('-0', '0'), true);
    });
    test('different numbers or non-numbers never collapse', () {
      for (final g in ['3.1', '30', '0.3', '4', '3,01', '', '-3', '3a']) {
        expect(sameTextAnswer(g, '3'), false, reason: '"$g" vs 3');
      }
      expect(sameTextAnswer('9007199254740993', '9007199254740992'), false);
      expect(sameTextAnswer('1.2.3', '1.2.3'), true);
      expect(sameTextAnswer('1.2.3', '1.2.30'), false);
    });
  });

  group('sameYesNoAnswer', () {
    test('typical correct answers (unchanged behaviour)', () {
      expect(sameYesNoAnswer('YES', 'YES'), true);
      expect(sameYesNoAnswer('NO', 'NO'), true);
      expect(sameYesNoAnswer('yes', 'YES'), true);
      expect(sameYesNoAnswer(' no ', 'NO'), true);
    });
    test('typical wrong answers (unchanged behaviour)', () {
      expect(sameYesNoAnswer('YES', 'NO'), false);
      expect(sameYesNoAnswer('NO', 'YES'), false);
      expect(sameYesNoAnswer('', 'YES'), false);
      expect(sameYesNoAnswer('maybe', 'YES'), false);
    });
    test('localized words and padding are the same answer', () {
      expect(sameYesNoAnswer(' yes ', 'YES'), true);
      expect(sameYesNoAnswer('Да', 'YES'), true);
      expect(sameYesNoAnswer('НЕТ', 'NO'), true);
      expect(sameYesNoAnswer('ha', 'YES'), true);
      expect(sameYesNoAnswer("Yo'q", 'NO'), true);
      expect(sameYesNoAnswer('Да', 'NO'), false);
    });
    test('non yes/no text falls back to trimmed case-insensitive equality', () {
      expect(sameYesNoAnswer('Not given', 'not given'), true);
      expect(sameYesNoAnswer('Not given', 'YES'), false);
    });
  });
}
