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
