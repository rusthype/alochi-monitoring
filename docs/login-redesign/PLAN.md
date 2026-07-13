# Login Screen Redesign — Plan

## Goal
Replace the wide/narrow split login layout with a single centered layout matching
the approved mockup (`login_redesign_mockup.html`): logo + title, two route buttons
(Alochi Monitoring active / Testlar disabled-"Tez kunda"), and an accordion that
reveals the login form when the active route is tapped.

Two files change:
1. `lib/features/auth/login_screen.dart` — major rewrite of `build()` + `_formPanel()`.
2. `lib/features/local_test/local_grade_screen.dart` — one-line PIN-hint removal.

## Approach — accordion = Option A (AnimatedSize)
`AnimatedSize` wrapping `_expanded ? Column(...) : const SizedBox.shrink()`.
- Simplest; no AnimationController/dispose.
- Matches the existing codebase (the old error box already used AnimatedSize).
- Option B (SizeTransition+controller) adds lifecycle complexity for no real gain.
- Option C (AnimatedContainer height:null) is broken — null height can't animate.
Wrap in `ClipRect` so the collapsing child doesn't paint outside bounds.

## What is preserved (do NOT touch)
- `checkOnlineWithRetry()`, `LoginScreen`, all `_Dot/_NetworkPainter/_NetworkBg` classes.
- All state fields + `_tryAutoLogin/_showForm/_checkOnline/_retryOnlineCheck/_login`.
- `_field()` helper and `_statusColor` getter.
- `build()`'s auto-login spinner branch + `CallbackShortcuts` Enter→`_login` wrapper.

## What changes
- ADD state field: `bool _expanded = false;`
- REPLACE `build()` layout body with the centered Stack (beige bg + `_NetworkBg` + scroll).
- DELETE `_wideLayout/_narrowLayout/_leftPanel/_circle/_infoRow` and `_formPanel()`.
- ADD `_routeButtons()`, `_routeButton(...)`, `_accordion()` helpers.
- Primary "Kirish" button KEEPS dynamic online/offline text+icon (user-confirmed).

## Tasks
- TASK_01 — login_screen.dart rewrite (see TASK_01).
- TASK_02 — local_grade_screen.dart PIN-hint fix (see TASK_02).

## Verify
- `flutter analyze` → 0 errors (see TASK_03 for full checklist).
- Run app: route buttons, accordion open/close, both login paths, disabled Testlar.
