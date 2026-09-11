// lib/features/diagnostic/data/diagnostic_option_item.dart
//
// Extracted out of diagnostic_test_runner_screen.dart so presentational
// widgets (DiagnosticOptionsGrid) can depend on this plain model instead of
// importing the screen file itself — avoids a circular import and keeps
// widget-test builds from pulling in the screen's full dependency graph
// (HeartbeatService, kiosk API client, etc.). Same precedent as
// DiagnosticHeaderBar's `_GradePill`, which is copied rather than imported
// from test_screen.dart for the same reason.
/// One rendered answer option: `key` is "A".."D", `text` is the display
/// string for that letter (already de/re-shuffled server-side).
class DiagnosticOptionItem {
  final String key;
  final String text;
  const DiagnosticOptionItem({required this.key, required this.text});
}

List<DiagnosticOptionItem> extractDiagnosticOptions(Map<String, dynamic> q) {
  final items = <DiagnosticOptionItem>[];
  for (final letter in ['A', 'B', 'C', 'D']) {
    final lowerKey = 'option_${letter.toLowerCase()}';
    final text = (q[lowerKey] ?? q[letter] ?? '').toString().trim();
    if (text.isNotEmpty) {
      items.add(DiagnosticOptionItem(key: letter, text: text));
    }
  }
  return items;
}
