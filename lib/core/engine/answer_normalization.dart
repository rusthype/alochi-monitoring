// lib/core/engine/answer_normalization.dart
// Shared English contraction-equivalence table, used by every free-text
// answer comparator (test_scorer, interhouse_scorer, unit1_runner,
// combined_runner) so "they are" and "they're" grade as the same answer.
//
// Keep this list in exact sync with the backend's mirror table
// (alochi_backend/apps/english_world/services/verify_result.py
// `_CONTRACTIONS`) — do not add or remove entries independently.
//
// Pure Dart — no Flutter imports.

/// Lowercase contraction → expanded-form map. Only contraction tokens
/// (apostrophe present) are keys, so expanding an already-expanded string
/// is a no-op — the function below is idempotent and safe to apply on both
/// the typed and the expected side of a comparison.
const Map<String, String> kContractions = {
  "they're": "they are",
  "it's": "it is",
  "he's": "he is",
  "she's": "she is",
  "we're": "we are",
  "you're": "you are",
  "i'm": "i am",
  "isn't": "is not",
  "aren't": "are not",
  "wasn't": "was not",
  "weren't": "were not",
  "don't": "do not",
  "doesn't": "does not",
  "didn't": "did not",
  "can't": "cannot",
  "won't": "will not",
  "i've": "i have",
  "you've": "you have",
  "we've": "we have",
  "they've": "they have",
  "i'll": "i will",
  "you'll": "you will",
  "he'll": "he will",
  "she'll": "she will",
  "we'll": "we will",
  "they'll": "they will",
  "haven't": "have not",
  "hasn't": "has not",
  "hadn't": "had not",
  "i'd": "i would",
  "he'd": "he would",
  "she'd": "she would",
  "we'd": "we would",
  "they'd": "they would",
  "let's": "let us",
  "there's": "there is",
  "that's": "that is",
  "what's": "what is",
  "who's": "who is",
};

/// Expands any contraction tokens in [s] to their full form.
///
/// Tokenizes on whitespace and replaces whole tokens found in
/// [kContractions]; non-matching tokens pass through unchanged. Assumes the
/// caller has already unified apostrophe glyphs to a straight `'` (this
/// function does not handle curly/Uzbek-modifier apostrophe variants).
String expandContractions(String s) {
  final trimmed = s.trim();
  if (trimmed.isEmpty) return trimmed;
  final tokens = trimmed.split(RegExp(r'\s+'));
  final expanded = tokens.map((t) => kContractions[t] ?? t).toList();
  return expanded.join(' ');
}

/// Canonical form of a plain decimal number, or null when [s] is not one.
///
/// Accepts an optional sign, digits and ONE `.` or `,` decimal separator
/// (`"3"`, `"3.0"`, `"3,0"`, `"-0,50"`); leading zeros of the integer part and
/// trailing zeros of the fraction are dropped (`"03,50"` -> `"3.5"`,
/// `"3.0"` -> `"3"`, `"-0"` -> `"0"`). Compared as STRINGS, never as doubles,
/// so two different numbers can never collapse into one. Callers pass an
/// already trimmed/normalized string.
String? canonicalNumber(String s) {
  final m = RegExp(r'^([+-]?)(\d+)(?:[.,](\d+))?$').firstMatch(s);
  if (m == null) return null;
  var int_ = m.group(2)!.replaceFirst(RegExp(r'^0+(?=\d)'), '');
  final frac = (m.group(3) ?? '').replaceFirst(RegExp(r'0+$'), '');
  final zero = int_ == '0' && frac.isEmpty;
  final sign = m.group(1) == '-' && !zero ? '-' : '';
  return frac.isEmpty ? '$sign$int_' : '$sign$int_.$frac';
}

/// True when [a] and [b] are both plain numbers of the same value
/// (`"3"` == `"3.0"` == `"3,0"`); never true for different numbers.
bool sameNumber(String a, String b) {
  final x = canonicalNumber(a.trim());
  return x != null && x == canonicalNumber(b.trim());
}

/// Language-independent form of a yes/no answer: `YES`, `NO`, or null when
/// [s] is neither. The stored value is always English `YES`/`NO`; the Uzbek /
/// Russian words are accepted too so an answer saved under a localized label
/// still scores the same.
String? canonicalYesNo(String s) {
  final t = s
      .trim()
      .toUpperCase()
      .replaceAll(RegExp("[’ʻʼ‘`´]"), "'")
      .replaceAll(RegExp(r'\s+'), ' ');
  switch (t) {
    case 'YES':
    case 'ДА':
    case 'HA':
      return 'YES';
    case 'NO':
    case 'НЕТ':
    case "YO'Q":
    case 'YOQ':
      return 'NO';
  }
  return null;
}

/// Legacy runners (Unit1 / Combined / Interhouse) text check: trimmed and
/// case-insensitive, or the same plain number (`"3"` == `"3.0"` == `"3,0"`).
/// Mirrors the generic engine's spelling / fill-blank number rule.
bool sameTextAnswer(String typed, String expected) {
  final t = typed.trim().toLowerCase();
  final e = expected.trim().toLowerCase();
  return t == e || sameNumber(t, e);
}

/// Legacy runners yes/no check: language-independent (`yes`, ` YES `, `ДА`
/// are all YES). When either side is not a yes/no word it falls back to
/// trimmed case-insensitive equality. The stored value is not changed.
bool sameYesNoAnswer(String given, String expected) {
  final g = canonicalYesNo(given);
  final e = canonicalYesNo(expected);
  if (g != null && e != null) return g == e;
  return given.trim().toLowerCase() == expected.trim().toLowerCase();
}
