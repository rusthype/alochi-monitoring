// lib/core/utils/student_name_formatter.dart
//
// Roster names from the school database come in either Uzbek-Cyrillic or
// Latin, ALL CAPS, with a trailing patronymic ("... DILSHOD O'G'LI" /
// "... Акмал кизи" / "... ANVAROVICH") the kiosk UI has no use for — this
// formats them down to "Surname Firstname" for card/roster display.
//
// Locale-aware display script: when the app's UI locale is Russian, proper
// nouns (school/student names) should render in Uzbek-Cyrillic to match the
// surrounding Russian chrome, not stay in Latin script. `toDisplayScript`
// below is the single entry point call sites use for that.
import 'package:flutter/widgets.dart' show Locale;

const Map<String, String> _cyrToLatin = {
  // Digraphs (1 Cyrillic char -> multi-char Latin) — case-sensitive pairs.
  'Ў': "O'", 'ў': "o'",
  'Ғ': "G'", 'ғ': "g'",
  'Қ': 'Q', 'қ': 'q',
  'Ҳ': 'H', 'ҳ': 'h',
  'Ш': 'Sh', 'ш': 'sh',
  'Ч': 'Ch', 'ч': 'ch',
  'Ю': 'Yu', 'ю': 'yu',
  'Я': 'Ya', 'я': 'ya',
  'Ё': 'Yo', 'ё': 'yo',
  'Ц': 'Ts', 'ц': 'ts',
  // Standard single-char mapping.
  'А': 'A', 'а': 'a',
  'Б': 'B', 'б': 'b',
  'В': 'V', 'в': 'v',
  'Г': 'G', 'г': 'g',
  'Д': 'D', 'д': 'd',
  'Е': 'E', 'е': 'e',
  'Ж': 'J', 'ж': 'j',
  'З': 'Z', 'з': 'z',
  'И': 'I', 'и': 'i',
  'Й': 'Y', 'й': 'y',
  'К': 'K', 'к': 'k',
  'Л': 'L', 'л': 'l',
  'М': 'M', 'м': 'm',
  'Н': 'N', 'н': 'n',
  'О': 'O', 'о': 'o',
  'П': 'P', 'п': 'p',
  'Р': 'R', 'р': 'r',
  'С': 'S', 'с': 's',
  'Т': 'T', 'т': 't',
  'У': 'U', 'у': 'u',
  'Ф': 'F', 'ф': 'f',
  'Х': 'X', 'х': 'x',
  'Ъ': "'", 'ъ': "'",
  'Ы': 'I', 'ы': 'i',
  'Ь': '', 'ь': '',
  'Э': 'E', 'э': 'e',
};

/// Transliterates Uzbek-Cyrillic text to Latin. Non-Cyrillic characters
/// (already-Latin names, digits, punctuation) pass through untouched.
String cyrillicToLatinUzbek(String input) {
  // ponytail: real Uzbek orthography renders Cyrillic 'е' as "ye" right
  // after a vowel (e.g. "БОҚИЕВ" -> "Boqiyev", not "Boqiev") — insert the
  // missing й/Й glide before the flat per-char table below so that case is
  // covered. Ceiling: doesn't handle 'е' as "ye" at the very start of a
  // word (no roster name in practice starts with Е); add a start-of-token
  // check if that ever surfaces.
  const vowels = 'АОУЫЭИаоуыэи';
  final glided = StringBuffer();
  for (var i = 0; i < input.length; i++) {
    final ch = input[i];
    glided.write(ch);
    if (vowels.contains(ch) && i + 1 < input.length) {
      final next = input[i + 1];
      if (next == 'Е') glided.write('Й');
      if (next == 'е') glided.write('й');
    }
  }

  final out = StringBuffer();
  for (final ch in glided.toString().split('')) {
    out.write(_cyrToLatin[ch] ?? ch);
  }
  return out.toString();
}

// Latin -> Cyrillic digraphs, mirroring _cyrToLatin's digraph entries in
// reverse. Checked case-insensitively, longest-match-first (they're all 2
// chars, so just "check these before falling back to single-char"). Output
// case follows the digraph's first matched character.
const List<MapEntry<String, String>> _latinDigraphs = [
  MapEntry("o'", 'ў'),
  MapEntry("g'", 'ғ'),
  MapEntry('sh', 'ш'),
  MapEntry('ch', 'ч'),
  MapEntry('yu', 'ю'),
  MapEntry('ya', 'я'),
  MapEntry('yo', 'ё'),
  MapEntry('ts', 'ц'),
];

// Single-char Latin -> Cyrillic, reverse of _cyrToLatin's single-char rows.
// ponytail: Latin 'i' is ambiguous (both И and Ы map to it going forward),
// as is 'e' (both Е and Э) — we pick the far more common И/Е. Upgrade to a
// dictionary lookup if a real name needs Ы/Э specifically.
const Map<String, String> _latinToCyrSingle = {
  'a': 'а', 'b': 'б', 'v': 'в', 'g': 'г', 'd': 'д', 'e': 'е', 'j': 'ж',
  'z': 'з', 'i': 'и', 'y': 'й', 'k': 'к', 'l': 'л', 'm': 'м', 'n': 'н',
  'o': 'о', 'p': 'п', 'q': 'қ', 'r': 'р', 's': 'с', 't': 'т', 'u': 'у',
  'f': 'ф', 'h': 'ҳ', 'x': 'х',
  "'": 'ъ',
};

bool _isUpperChar(String c) =>
    c.toUpperCase() == c && c.toLowerCase() != c.toUpperCase();

/// Transliterates Latin-Uzbek text to Uzbek-Cyrillic — the mirror image of
/// [cyrillicToLatinUzbek]. Non-Latin characters (already-Cyrillic names,
/// digits, punctuation) pass through untouched, since neither the digraph
/// list nor the single-char map matches them.
String latinToCyrillicUzbek(String input) {
  // ponytail: cyrillicToLatinUzbek inserts an artificial "y" before "e"
  // after a vowel to spell out the ye-glide (БОҚИЕВ -> Boqiyev) — undo that
  // here so the round trip lands on "Боқиев", not "Бокийев". Ceiling: same
  // as the forward glide, doesn't cover a word-initial case.
  final degl = input.replaceAllMapped(
    RegExp(r'(?<=[AOUIEaouie])[Yy](?=[Ee])'),
    (_) => '',
  );

  final out = StringBuffer();
  var i = 0;
  while (i < degl.length) {
    final two = i + 2 <= degl.length ? degl.substring(i, i + 2) : null;
    final digraph = two == null
        ? null
        : _latinDigraphs
            .cast<MapEntry<String, String>?>()
            .firstWhere((d) => d!.key == two.toLowerCase(), orElse: () => null);
    if (digraph != null) {
      final cyr = digraph.value;
      out.write(_isUpperChar(degl[i]) ? cyr.toUpperCase() : cyr);
      i += 2;
      continue;
    }
    final ch = degl[i];
    final mapped = _latinToCyrSingle[ch.toLowerCase()];
    if (mapped == null || mapped.isEmpty) {
      out.write(ch);
    } else {
      out.write(_isUpperChar(ch) ? mapped.toUpperCase() : mapped);
    }
    i++;
  }
  return out.toString();
}

/// True if [s] contains any Uzbek-Cyrillic character, so call sites can
/// decide whether a script conversion is needed at all instead of risking a
/// double-conversion or mangling already-correct-script text.
bool looksCyrillic(String s) {
  for (final rune in s.runes) {
    if (rune >= 0x0400 && rune <= 0x04FF) return true;
  }
  return false;
}

/// Locale-aware display script for proper nouns (school/student names):
/// Russian UI -> Uzbek-Cyrillic, Uzbek UI -> Latin. No-op if the text is
/// already in the target script.
String toDisplayScript(String raw, Locale locale) {
  if (raw.isEmpty) return raw;
  final cyrillic = looksCyrillic(raw);
  if (locale.languageCode == 'ru') {
    return cyrillic ? raw : latinToCyrillicUzbek(raw);
  }
  return cyrillic ? cyrillicToLatinUzbek(raw) : raw;
}

const _patronymicMarkers = {
  "o'g'li",
  "og'li",
  'ugli',
  'qizi',
  'kizi',
};

bool _isPatronymicToken(String token) {
  final t = token.toLowerCase();
  return _patronymicMarkers.contains(t) ||
      t.endsWith('vich') ||
      t.endsWith('vna');
}

String _titleCase(String token) {
  if (token.isEmpty) return token;
  return token[0].toUpperCase() + token.substring(1).toLowerCase();
}

/// Cyrillic-or-Latin, ALL-CAPS-with-patronymic roster name -> "Surname
/// Firstname" for display (e.g. kiosk student-select cards).
String formatStudentDisplayName(String rawName) {
  final tokens = cyrillicToLatinUzbek(rawName)
      .split(RegExp(r'\s+'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .where((t) => !_isPatronymicToken(t));
  return tokens.take(2).map(_titleCase).join(' ');
}
