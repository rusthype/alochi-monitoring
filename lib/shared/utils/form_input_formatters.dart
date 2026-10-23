// lib/shared/utils/form_input_formatters.dart
//
// Input helpers for the "Bola qo'shish" dialog: per-word title-casing for
// names and a "KK.OO.YYYY" masked birth date with on-the-fly validation.
import 'package:flutter/services.dart';

// ---- names -----------------------------------------------------------------

// A new word starts after these (an apostrophe does NOT start a word:
// O'g'li, G'ofur, Sa'dulla). '.' and ',' are included so initials in a parent
// F.I.O. ("Karimov A.B.") are not lowercased.
const _wordBreaks = {0x20, 0x2D, 0x2E, 0x2C}; // space - . ,

/// "VALIXON ali-AKA o'G'LI" -> "Valixon Ali-Aka O'g'li". Latin and Cyrillic.
/// Never changes the string length (a char whose case-mapping changes length,
/// e.g. German sharp s, is left as typed), so selection/composing stay valid.
String titleCaseName(String s) {
  final b = StringBuffer();
  var wordStart = true;
  for (final r in s.runes) {
    final ch = String.fromCharCode(r);
    final mapped = wordStart ? ch.toUpperCase() : ch.toLowerCase();
    b.write(mapped.length == ch.length ? mapped : ch);
    wordStart = _wordBreaks.contains(r);
  }
  return b.toString();
}

/// Title-cases every word as the user types (caps lock / paste proof).
class TitleCaseNameFormatter extends TextInputFormatter {
  const TitleCaseNameFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final out = titleCaseName(newValue.text);
    // Same length -> selection and IME composing region stay as they are.
    return out == newValue.text ? newValue : newValue.copyWith(text: out);
  }
}

// ---- birth date ------------------------------------------------------------

/// Mirrors the backend `invalid_birth_date` rule: year >= 1990, not future.
final DateTime kBirthDateMin = DateTime(1990);

enum BirthDateError { incomplete, invalid, future, tooOld }

String _digitsOf(String s) =>
    String.fromCharCodes(s.codeUnits.where((c) => c >= 0x30 && c <= 0x39));

/// "15032016" -> "15.03.2016" (dots only appear once more digits follow).
String formatBirthDigits(String digits) {
  final d = digits.length > 8 ? digits.substring(0, 8) : digits;
  final b = StringBuffer(d.substring(0, d.length < 2 ? d.length : 2));
  if (d.length > 2) b.write('.${d.substring(2, d.length < 4 ? d.length : 4)}');
  if (d.length > 4) b.write('.${d.substring(4)}');
  return b.toString();
}

/// Digits-only mask that auto-inserts the dots and keeps the caret next to the
/// same digit.
class BirthDateMaskFormatter extends TextInputFormatter {
  const BirthDateMaskFormatter();

  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    final text = newValue.text;
    final sel = newValue.selection;
    final cursor =
        sel.isValid ? sel.extentOffset.clamp(0, text.length) : text.length;
    final kept = StringBuffer();
    var before = 0; // kept digits left of the caret
    for (var i = 0; i < text.length && kept.length < 8; i++) {
      final c = text.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) continue;
      kept.writeCharCode(c);
      if (i < cursor) before++;
    }
    final out = formatBirthDigits(kept.toString());
    final pos = before + (before > 2 ? 1 : 0) + (before > 4 ? 1 : 0);
    return TextEditingValue(
      text: out,
      selection: TextSelection.collapsed(offset: pos.clamp(0, out.length)),
    );
  }
}

/// Parses/validates the masked text. Empty is fine (optional field):
/// `(date: null, error: null)`. Day/month are rejected as soon as they are
/// typed; [BirthDateError.incomplete] means "valid so far, not finished".
({DateTime? date, BirthDateError? error}) checkBirthDate(String text,
    {DateTime? today}) {
  final d = _digitsOf(text);
  if (d.isEmpty) return (date: null, error: null);
  if (d.length >= 2) {
    final day = int.parse(d.substring(0, 2));
    if (day < 1 || day > 31) return (date: null, error: BirthDateError.invalid);
  }
  if (d.length >= 4) {
    final month = int.parse(d.substring(2, 4));
    if (month < 1 || month > 12) {
      return (date: null, error: BirthDateError.invalid);
    }
  }
  if (d.length < 8) return (date: null, error: BirthDateError.incomplete);
  final day = int.parse(d.substring(0, 2));
  final month = int.parse(d.substring(2, 4));
  final year = int.parse(d.substring(4));
  final date = DateTime(year, month, day);
  if (date.day != day || date.month != month) {
    return (date: null, error: BirthDateError.invalid); // 31.02 etc.
  }
  final now = today ?? DateTime.now();
  if (date.isAfter(DateTime(now.year, now.month, now.day))) {
    return (date: null, error: BirthDateError.future);
  }
  if (date.isBefore(kBirthDateMin)) {
    return (date: null, error: BirthDateError.tooOld);
  }
  return (date: date, error: null);
}

String formatBirthDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year.toString().padLeft(4, '0')}';
