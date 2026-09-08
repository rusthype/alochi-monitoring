// lib/core/utils/student_name_formatter.dart
//
// Roster names from the school database come in either Uzbek-Cyrillic or
// Latin, ALL CAPS, with a trailing patronymic ("... DILSHOD O'G'LI" /
// "... Акмал кизи" / "... ANVAROVICH") the kiosk UI has no use for — this
// formats them down to "Surname Firstname" for card/roster display.

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
  'Ъ': '', 'ъ': '',
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
