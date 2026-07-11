// lib/core/services/update_service.dart
// Checks GitHub Releases for a newer app version at startup and shows a
// dismissible "update available" dialog — link-out only, no auto-install.
// See docs/superpowers/specs/2026-07-11-monitoring-flutter-update-mechanism-design.md
// (in the alochi monorepo) for the full design rationale.

final RegExp _setupExePattern =
    RegExp(r'^AlochiMonitoring-(\d+)\.(\d+)\.(\d+)-Setup\.exe$');

/// True if [remote] is strictly newer than [local] (both "X.Y.Z" strings).
/// Numeric comparison, not string comparison — "1.0.9" vs "1.0.10" must
/// compare correctly. Returns false (not an error) for malformed input,
/// since this only gates whether to show a UI dialog.
bool isNewerVersion(String remote, String local) {
  final r = _parseVersionParts(remote);
  final l = _parseVersionParts(local);
  if (r == null || l == null) return false;
  for (var i = 0; i < 3; i++) {
    if (r[i] != l[i]) return r[i] > l[i];
  }
  return false;
}

/// Extracts the highest version among AlochiMonitoring-X.Y.Z-Setup.exe
/// assets in a GitHub release's `assets` list (raw JSON, already decoded).
/// The 'latest' release accumulates old Setup.exe assets over time (never
/// deleted), so this MUST scan all matches and pick the max — not the first.
/// Returns null if no matching asset is found.
String? maxSetupExeVersion(List<dynamic> assets) {
  List<int>? best;
  for (final asset in assets) {
    if (asset is! Map) continue;
    final name = asset['name'];
    if (name is! String) continue;
    final match = _setupExePattern.firstMatch(name);
    if (match == null) continue;
    final parts = [
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    ];
    if (best == null || _compareParts(parts, best) > 0) {
      best = parts;
    }
  }
  if (best == null) return null;
  return '${best[0]}.${best[1]}.${best[2]}';
}

List<int>? _parseVersionParts(String version) {
  final segments = version.split('.');
  if (segments.length < 3) return null;
  final parts = <int>[];
  for (var i = 0; i < 3; i++) {
    final n = int.tryParse(segments[i]);
    if (n == null) return null;
    parts.add(n);
  }
  return parts;
}

int _compareParts(List<int> a, List<int> b) {
  for (var i = 0; i < 3; i++) {
    if (a[i] != b[i]) return a[i] - b[i];
  }
  return 0;
}
