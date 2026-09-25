# Diagnostic Class Language Auto-Switch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** When an operator picks a class in the diagnostic test flow, the three screens shown after that point (student select, test runner, finished) render in the selected class's language (`ru` or `uz`) — without touching the app-wide language preference used by login, settings, and every other screen.

**Architecture:** A new, unpersisted `diagnosticLocaleProvider` (Riverpod `Notifier<Locale>`) is set from `DiagnosticClassSelectScreen._selectClass()`. The three post-selection routes (`/diagnostic_student_select`, `/diagnostic_test_runner`, `/diagnostic_finished`) are grouped under a new `ShellRoute` in `app_router.dart`, whose builder wraps them in `Localizations.override(locale: ref.watch(diagnosticLocaleProvider), ...)`. This scopes the language switch to exactly those three screens; the app-wide `localeProvider` (`core/locale/locale_provider.dart`, SharedPreferences-backed) is never written to, so it keeps reflecting the operator's own preference everywhere else. Three call sites that read the app-wide locale directly (bypassing the widget tree) for student-name script transliteration are switched to `Localizations.localeOf(context)` so they follow the same override.

**Tech Stack:** Flutter, Riverpod (`flutter_riverpod`, `Notifier`/`NotifierProvider`), go_router 17 (`ShellRoute`).

**Context (why this plan exists):** A grilling interview (`docs/PROMPT_DIAGNOSTIC_CLASS_LANGUAGE_AUTO_SWITCH.md`) surfaced that the original prompt's suggested approach — calling `localeProvider.notifier.setLocale(...)` directly — would leak into the entire app (login, teacher/student settings, `language_switcher` widget) because `localeProvider` is global and persisted, and the diagnostic flow is not a locked kiosk (it routes back through the shared login/root screen after every student). The interview settled on a scoped override instead, confined to exactly the three screens that actually need the class's language.

**Prerequisite (not a task in this plan):** Per `superpowers:using-git-worktrees`, create an isolated worktree before starting:
```bash
cd ~/PycharmProjects/AlochiSchool/alochi-monitoring-flutter
git worktree add .worktrees/diagnostic-class-language-auto-switch -b feat/diagnostic-class-language-auto-switch origin/main
cd .worktrees/diagnostic-class-language-auto-switch
```
All file paths below are relative to that worktree root.

---

### Task 1: Scoped diagnostic locale provider

**Files:**
- Create: `lib/features/diagnostic/providers/diagnostic_locale_provider.dart`

- [ ] **Step 1: Write the provider**

```dart
// lib/features/diagnostic/providers/diagnostic_locale_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Scoped UI locale for the diagnostic test flow (student select, test
/// runner, finished screens), set from the selected class's language in
/// [DiagnosticClassSelectScreen._selectClass]. Deliberately NOT persisted
/// (unlike the app-wide `localeProvider` in core/locale/locale_provider.dart)
/// — it only needs to live for the current kiosk session, and persisting it
/// would leak the last-tested class's language into the operator's own next
/// login on this device.
final diagnosticLocaleProvider =
    NotifierProvider<DiagnosticLocaleNotifier, Locale>(() {
  return DiagnosticLocaleNotifier();
});

class DiagnosticLocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('uz');

  void setLocale(Locale locale) {
    state = locale;
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/diagnostic/providers/diagnostic_locale_provider.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/diagnostic/providers/diagnostic_locale_provider.dart
git commit -m "feat(diagnostic): add scoped, unpersisted diagnostic locale provider"
```

---

### Task 2: ShellRoute wrapper widget

**Files:**
- Create: `lib/features/diagnostic/widgets/diagnostic_locale_shell.dart`

- [ ] **Step 1: Write the wrapper widget**

```dart
// lib/features/diagnostic/widgets/diagnostic_locale_shell.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/diagnostic_locale_provider.dart';

/// Wraps the post-class-selection diagnostic screens (student select, test
/// runner, finished) so their UI locale follows the selected class's
/// language, without touching the app-wide `localeProvider` — which would
/// otherwise leak into unrelated screens (login, settings, teacher UI) that
/// the same device cycles through between diagnostic sessions.
class DiagnosticLocaleShell extends ConsumerWidget {
  final Widget child;

  const DiagnosticLocaleShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(diagnosticLocaleProvider);
    return Localizations.override(
      context: context,
      locale: locale,
      child: child,
    );
  }
}
```

- [ ] **Step 2: Verify it compiles**

Run: `flutter analyze lib/features/diagnostic/widgets/diagnostic_locale_shell.dart`
Expected: `No issues found!`

- [ ] **Step 3: Commit**

```bash
git add lib/features/diagnostic/widgets/diagnostic_locale_shell.dart
git commit -m "feat(diagnostic): add ShellRoute wrapper that overrides Locale from diagnosticLocaleProvider"
```

---

### Task 3: Wire the ShellRoute into the router

**Files:**
- Modify: `lib/core/router/app_router.dart:45` (import), `lib/core/router/app_router.dart:396-453` (route wrapping)

- [ ] **Step 1: Add the import**

In `lib/core/router/app_router.dart`, after the existing diagnostic imports (line 45):

```dart
// Diagnostic kiosk flow
import '../../features/diagnostic/screens/diagnostic_school_select_screen.dart';
import '../../features/diagnostic/screens/diagnostic_session_setup_screen.dart';
import '../../features/diagnostic/screens/diagnostic_class_select_screen.dart';
import '../../features/diagnostic/screens/diagnostic_student_select_screen.dart';
import '../../features/diagnostic/screens/diagnostic_test_runner_screen.dart';
import '../../features/diagnostic/screens/diagnostic_finished_screen.dart';
import '../../features/diagnostic/widgets/diagnostic_locale_shell.dart';
```

- [ ] **Step 2: Wrap the three post-selection routes in a ShellRoute**

Replace the three top-level `GoRoute`s for `/diagnostic_student_select`, `/diagnostic_test_runner`, and `/diagnostic_finished` (currently lines 396-453, sitting directly in the outer `routes: [...]` list) with a single `ShellRoute` containing the same three `GoRoute`s as children. Only the wrapping changes — every `builder` body stays byte-for-byte identical:

```dart
      ShellRoute(
        builder: (context, state, child) =>
            DiagnosticLocaleShell(child: child),
        routes: [
          GoRoute(
              path: '/diagnostic_student_select',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return DiagnosticStudentSelectScreen(
                  schoolId: extra['schoolId'] as String? ?? '',
                  schoolName: extra['schoolName'] as String? ?? '',
                  schoolCode: extra['schoolCode'] as String? ?? '',
                  classLabel: extra['classLabel'] as String? ?? '',
                  language: extra['language'] as String? ?? 'uz',
                  hasWebTest: extra['hasWebTest'] as bool? ?? false,
                  webTestKey: extra['webTestKey'] as String? ?? '',
                );
              }),
          GoRoute(
              path: '/diagnostic_test_runner',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                final rawPrefetched = extra['prefetchedSubjects'];
                final rawAllSubjects = extra['prefetchedAllSubjects'];
                return DiagnosticTestRunnerScreen(
                  attemptId: extra['attemptId'] as String? ?? '',
                  studentName: extra['studentName'] as String? ?? '',
                  grade: extra['grade'] as int? ?? 1,
                  schoolCode: extra['schoolCode'] as String? ?? '',
                  language: extra['language'] as String? ?? 'uz',
                  schoolName: extra['schoolName'] as String? ?? '',
                  classLabel: extra['classLabel'] as String? ?? '',
                  schoolId: extra['schoolId'] as String? ?? '',
                  hasWebTest: extra['hasWebTest'] as bool? ?? false,
                  webTestKey: extra['webTestKey'] as String? ?? '',
                  prefetchedSubjects: rawPrefetched is Map
                      ? rawPrefetched.map((k, v) => MapEntry(
                          k.toString(), Map<String, dynamic>.from(v as Map)))
                      : null,
                  prefetchedAllSubjects: rawAllSubjects is List
                      ? rawAllSubjects.map((e) => e.toString()).toList()
                      : null,
                );
              }),
          GoRoute(
              path: '/diagnostic_finished',
              builder: (context, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return DiagnosticFinishedScreen(
                  studentName: extra['studentName'] as String?,
                  subjectsCompleted:
                      (extra['subjectsCompleted'] as List?)?.cast<String>() ??
                          const [],
                  schoolId: extra['schoolId'] as String? ?? '',
                  schoolName: extra['schoolName'] as String? ?? '',
                  schoolCode: extra['schoolCode'] as String? ?? '',
                  classLabel: extra['classLabel'] as String? ?? '',
                  language: extra['language'] as String? ?? '',
                  hasWebTest: extra['hasWebTest'] as bool? ?? false,
                  webTestKey: extra['webTestKey'] as String? ?? '',
                );
              }),
        ],
      ),
```

`/diagnostic_school_select`, `/diagnostic_session_setup`, and `/diagnostic_class_select` (lines 372-395) stay exactly where they are, outside the `ShellRoute`, unchanged — they must keep following the app-wide `localeProvider` since the class's language isn't known yet at those points, and changing that would override the operator's own language preference on those three screens.

- [ ] **Step 3: Verify it compiles**

Run: `flutter analyze lib/core/router/app_router.dart`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/core/router/app_router.dart
git commit -m "feat(diagnostic): scope student-select/test-runner/finished routes under DiagnosticLocaleShell"
```

---

### Task 4: Set the locale when a class is selected

**Files:**
- Modify: `lib/features/diagnostic/screens/diagnostic_class_select_screen.dart`

- [ ] **Step 1: Add imports**

At the top of `lib/features/diagnostic/screens/diagnostic_class_select_screen.dart`, after the existing `go_router` import:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:alochi_monitoring/l10n/app_localizations.dart';
import '../../../core/api/api_client.dart' show ApiException;
import '../../../shared/theme/app_theme.dart';
import '../data/diagnostic_kiosk_api.dart';
import '../providers/diagnostic_locale_provider.dart';
import '../widgets/diagnostic_widgets.dart';
```

- [ ] **Step 2: Convert the widget to ConsumerStatefulWidget**

Change (currently lines 35-53):

```dart
class DiagnosticClassSelectScreen extends StatefulWidget {
  final String schoolId;
  final String schoolName;
  final String schoolCode;

  const DiagnosticClassSelectScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
    this.schoolCode = '',
  });

  @override
  State<DiagnosticClassSelectScreen> createState() =>
      _DiagnosticClassSelectScreenState();
}

class _DiagnosticClassSelectScreenState
    extends State<DiagnosticClassSelectScreen> {
```

to:

```dart
class DiagnosticClassSelectScreen extends ConsumerStatefulWidget {
  final String schoolId;
  final String schoolName;
  final String schoolCode;

  const DiagnosticClassSelectScreen({
    super.key,
    required this.schoolId,
    required this.schoolName,
    this.schoolCode = '',
  });

  @override
  ConsumerState<DiagnosticClassSelectScreen> createState() =>
      _DiagnosticClassSelectScreenState();
}

class _DiagnosticClassSelectScreenState
    extends ConsumerState<DiagnosticClassSelectScreen> {
```

- [ ] **Step 3: Set the diagnostic locale in `_selectClass`**

Change (currently lines 91-102):

```dart
  void _selectClass(String classLabel, String language,
      {bool hasWebTest = false, String webTestKey = ''}) {
    context.push('/diagnostic_student_select', extra: {
      'schoolId': widget.schoolId,
      'schoolName': widget.schoolName,
      'schoolCode': widget.schoolCode,
      'classLabel': classLabel,
      'language': language,
      'hasWebTest': hasWebTest,
      'webTestKey': webTestKey,
    });
  }
```

to:

```dart
  void _selectClass(String classLabel, String language,
      {bool hasWebTest = false, String webTestKey = ''}) {
    final langCode = language.toLowerCase().trim() == 'ru' ? 'ru' : 'uz';
    ref.read(diagnosticLocaleProvider.notifier).setLocale(Locale(langCode));
    context.push('/diagnostic_student_select', extra: {
      'schoolId': widget.schoolId,
      'schoolName': widget.schoolName,
      'schoolCode': widget.schoolCode,
      'classLabel': classLabel,
      'language': language,
      'hasWebTest': hasWebTest,
      'webTestKey': webTestKey,
    });
  }
```

(`language` — the raw value forwarded to the next screen for API calls/display — is untouched; only the new `langCode` local is used for the locale switch, so this doesn't change what the backend or downstream screens receive.)

- [ ] **Step 4: Verify it compiles**

Run: `flutter analyze lib/features/diagnostic/screens/diagnostic_class_select_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/diagnostic/screens/diagnostic_class_select_screen.dart
git commit -m "feat(diagnostic): set diagnosticLocaleProvider from the selected class's language"
```

---

### Task 5: Fix student-name script transliteration to follow the override

**Files:**
- Modify: `lib/features/diagnostic/screens/diagnostic_student_select_screen.dart:19,487`
- Modify: `lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart:27,1599-1600`
- Modify: `lib/features/diagnostic/screens/diagnostic_finished_screen.dart:10,130`

These three screens transliterate student names for display (`toDisplayScript`, from `core/utils/student_name_formatter.dart`, already imported in all three) using the *app-wide* locale, read directly off the provider container instead of the widget tree. That bypasses the `Localizations.override` from Task 3, so names would keep the operator's old script even after the UI strings around them switch language. Each of these files uses `flutter_riverpod`/`core/locale/locale_provider.dart` for exactly this one line (verified: `rg -c "ref\.|ConsumerState|ConsumerWidget|ProviderScope"` returns `1` for each file) — after the fix, both imports become unused and must be removed too.

- [ ] **Step 1: Fix `diagnostic_student_select_screen.dart`**

Remove this import (line 19):
```dart
import '../../../core/locale/locale_provider.dart';
```
and this import (line 14):
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Change (currently lines 486-487):
```dart
    final locale =
        ProviderScope.containerOf(context, listen: false).read(localeProvider);
```
to:
```dart
    final locale = Localizations.localeOf(context);
```

- [ ] **Step 2: Fix `diagnostic_test_runner_screen.dart`**

Remove this import (line 27):
```dart
import '../../../core/locale/locale_provider.dart';
```
and this import (line 17):
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Change (currently lines 1597-1600):
```dart
                      studentName: toDisplayScript(
                          formatStudentDisplayName(widget.studentName),
                          ProviderScope.containerOf(context, listen: false)
                              .read(localeProvider)),
```
to:
```dart
                      studentName: toDisplayScript(
                          formatStudentDisplayName(widget.studentName),
                          Localizations.localeOf(context)),
```

- [ ] **Step 3: Fix `diagnostic_finished_screen.dart`**

Remove this import (line 10):
```dart
import '../../../core/locale/locale_provider.dart';
```
and this import (line 7):
```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
```

Change (currently lines 129-130):
```dart
    final locale =
        ProviderScope.containerOf(context, listen: false).read(localeProvider);
```
to:
```dart
    final locale = Localizations.localeOf(context);
```

- [ ] **Step 4: Verify it compiles with no unused-import warnings**

Run: `flutter analyze lib/features/diagnostic/screens/diagnostic_student_select_screen.dart lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart lib/features/diagnostic/screens/diagnostic_finished_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Commit**

```bash
git add lib/features/diagnostic/screens/diagnostic_student_select_screen.dart lib/features/diagnostic/screens/diagnostic_test_runner_screen.dart lib/features/diagnostic/screens/diagnostic_finished_screen.dart
git commit -m "fix(diagnostic): read locale from Localizations instead of the global provider for name script"
```

---

### Task 6: Full verification and manual QA

**Files:** none (verification only)

- [ ] **Step 1: Full static analysis**

Run: `flutter analyze`
Expected: `No issues found!` (zero errors, zero warnings, zero infos)

- [ ] **Step 2: Manual QA — Russian class**

Run the app on a simulator/device connected to a real backend school with at least one Russian-language class and one Uzbek-language class (`flutter run`). Log in, navigate Diagnostika → pick the school → pick a **Russian** class (language `ru`):
- Confirm the student-select screen shows Russian strings (e.g. "Выберите ученика") and any listed student names render in Cyrillic script.
- Start a test; confirm the test-runner screen's buttons/labels are Russian ("Далее", "Черновик", "Завершить тест") and the header's student name is Cyrillic.
- Finish the test; confirm the finished screen is Russian and the greeting's student name is Cyrillic.

- [ ] **Step 3: Manual QA — Uzbek class, and no bleed into other screens**

Go back to class select and pick an **Uzbek** class (language `uz`):
- Confirm all three screens switch back to Uzbek immediately ("O'quvchini tanlang", "Savol", "Qoralama", "Testni yakunlash") with names in Latin script.
- Exit the diagnostic flow back to the login/root screen (or navigate to student settings if reachable from this build). Confirm the app's own language setting there still reflects whatever the operator had set before starting diagnostics — i.e. it was never changed by any of the above steps.

- [ ] **Step 4: Push the branch** (working branch only — no merge to `main`, no release, per project policy)

```bash
git push origin feat/diagnostic-class-language-auto-switch
```

---

## Verification Summary

| Requirement (from PROMPT_DIAGNOSTIC_CLASS_LANGUAGE_AUTO_SWITCH.md) | Covered by |
|---|---|
| Ru sinf tanlansa keyingi ekranlar ruscha ochilishi | Task 3 (ShellRoute), Task 4 (setLocale) |
| Uz sinf tanlansa keyingi ekranlar o'zbekcha ochilishi | Task 3, Task 4 |
| Barcha keyingi ekranlar (o'quvchi tanlash, test, natija) mos til | Task 3 covers the 3 routes; Task 5 covers name-script consistency within them |
| `flutter analyze` → 0 xato | Task 6, Step 1 |
| (Interview addition) Global til/operator sozlamalariga ta'sir qilmaslik | Task 1 (unpersisted provider), Task 3 (only 3 routes shelled, school_select/session_setup/class_select excluded) |
