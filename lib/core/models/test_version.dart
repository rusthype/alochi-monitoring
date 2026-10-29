// lib/core/models/test_version.dart
//
// ONE definition of a test package's version for the catalog, the cache, the
// parsed TestSpec and the attempt-version comparisons. A package that carries
// no (or an unreadable) `version` is 0 = "unknown" everywhere, so the cache
// (stores 0) and the spec can never disagree about it.

/// Parses a `version` JSON value; missing / unreadable / negative -> 0.
int parseTestVersion(Object? raw) {
  final n = raw is num ? raw.toInt() : int.tryParse(raw?.toString() ?? '');
  return n == null || n < 0 ? 0 : n;
}

/// True only when BOTH sides are known (> 0) and differ. An unknown version
/// on either side is "unchanged": the attempt is never treated as stale just
/// because a package never declared a version.
bool testVersionChanged(int? saved, int? current) =>
    saved != null &&
    current != null &&
    saved > 0 &&
    current > 0 &&
    saved != current;
