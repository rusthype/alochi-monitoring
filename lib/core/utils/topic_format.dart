// lib/core/utils/topic_format.dart
// Shared shape-normalizers: convert the two legacy per-test-runner "detail"
// shapes (Unit1/Combined's sections list, Interhouse's engTopics entries)
// into the topics:[{name,correct,total}] shape core_views.py's
// _extract_topics() reads (see docs/superpowers/specs/2026-07-10-flutter-topic-format-alignment-design.md
// in the alochi monorepo). No `code`/`pct` field — _extract_topics never
// reads them, so adding them would be dead weight.

List<Map<String, dynamic>> topicsFromSections(
  List<Map<String, dynamic>> sections,
) {
  return sections
      .map((s) => {
            'name': s['name'],
            'correct': s['cor'],
            'total': s['tot'],
          })
      .toList();
}

List<Map<String, dynamic>> topicsFromEngEntries(
  List<MapEntry<String, ({int ok, int tot})>> entries,
) {
  return entries
      .map((e) => {
            'name': e.key,
            'correct': e.value.ok,
            'total': e.value.tot,
          })
      .toList();
}
