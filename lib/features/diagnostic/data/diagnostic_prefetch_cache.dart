// lib/features/diagnostic/data/diagnostic_prefetch_cache.dart
//
// App-process-lifetime, in-memory-only cache for diagnostic bulk-prefetch
// state — deliberately NOT tied to DiagnosticStudentSelectScreen's State
// object. Needed because diagnostic_finished_screen.dart's `context.go('/')`
// (fired on every single student's test completion, either manually or via
// its 15s auto-return timer) resets the ENTIRE go_router navigation stack,
// destroying the school/class/student-select screens and, with them, any
// State-held cache — silently discarding a bulk "download whole class" pass
// the moment the FIRST student finishes. Hoisting the cache here lets it
// survive that reset for as long as the app process runs. This is STILL
// "memory only" per the explicit prior decision to not reintroduce a disk
// cache (see git history: a DiagnosticPackageCache disk cache was removed
// for sqflite/FakeAsync test-isolation flakiness) — it just lives longer
// than one screen visit, not across app restarts.
import 'package:flutter/foundation.dart';
import '../widgets/diagnostic_widgets.dart' show StudentPrefetchStatus;

class DiagnosticPrefetchCache {
  DiagnosticPrefetchCache._();
  static final DiagnosticPrefetchCache instance = DiagnosticPrefetchCache._();

  final Map<String, Map<String, Map<String, dynamic>>> peekCache = {};
  final Map<String, List<String>> allSubjectsCache = {};
  final Map<String, StudentPrefetchStatus> studentStatus = {};
  final Map<String, bool> studentHasOnlineOnlySubject = {};

  /// Test-only — clears all cached state so widget tests don't leak data
  /// between test cases (this is a real global singleton, shared across
  /// the whole test process unlike a fresh State object per test).
  @visibleForTesting
  void reset() {
    peekCache.clear();
    allSubjectsCache.clear();
    studentStatus.clear();
    studentHasOnlineOnlySubject.clear();
  }
}
