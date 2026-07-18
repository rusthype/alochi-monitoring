# Login screen — split-panel + pseudo-3D hero visual

**Date:** 2026-07-18
**Status:** Approved by user, pending implementation plan
**File touched:** `lib/features/auth/login_screen.dart` (layout only)
**New file:** `lib/features/auth/widgets/hero_visual_panel.dart`

## Context

The current login screen (`login_screen.dart`, `_LoginScreenState.build()`,
roughly L372–517) renders a single centered column on top of an animated
dotted "network" background (`_NetworkBg`/`_NetworkPainter`, L53–172): logo,
title, subtitle, language switcher, `_routeButtons()`, `_accordion()` (the
login form), and a sync/history row. Two floating buttons
(`_newTestsButton()` top-left, `_updateBadge()` top-right) sit above
everything via `Positioned` in the outer `Stack`.

The user supplied two reference images:
- **Current app screenshot** — the centered single-column layout described
  above (confirms current state, no surprises).
- **A design reference mockup** — a split-panel layout: a left panel with a
  glowing pedestal, a rising light beam, and floating soft-blurred orbs
  (a "hologram" look), and a right panel with the login card content.

Goal: bring the split-panel + animated visual treatment from the reference
into the real app, on wide windows only, while keeping every existing
interactive element and its behavior untouched.

## Decisions (locked via brainstorming Q&A)

1. **Animation technique:** pseudo-3D via `CustomPainter` + a single
   `AnimationController`, matching the existing `_NetworkBg` pattern in
   spirit. No new packages (ruled out `model_viewer_plus`/`flutter_cube` —
   too heavy for a desktop login screen, uncertain Windows support).
2. **Layout breakpoint:** split-panel only when window width ≥ 900px.
   Below that, the screen is **pixel-identical to today** — same
   `_NetworkBg`, same single-column `Column`, same everything. No new
   behavior to regress on narrow windows.
3. **Color scheme:** the hero visual uses `AppColors.brand` (existing brand
   green) as the primary glow/beam color, over the existing cream
   background, with muted/desaturated versions of the `_Dot` palette
   (`0xFF4A90D9`, `0xFFF97316`, `0xFF7C3AED`, `0xFF0D9488`, `0xFFE11D48`) for
   secondary orbs — not the reference image's purple gradient. Visual must
   read as "Alochi", not as a copy of the mockup's palette.

## Architecture

### New file: `lib/features/auth/widgets/hero_visual_panel.dart`

`login_screen.dart` is already 1928 lines. The hero visual is a
self-contained, purely decorative unit with no dependency on
`_LoginScreenState` — it takes no external state and exposes no callbacks.
It belongs in its own file both to keep it independently readable/testable
and to avoid growing the already-large login file further.

Contents:

```dart
class HeroVisualPanel extends StatefulWidget {
  const HeroVisualPanel({super.key});
}

class _HeroVisualPanelState extends State<HeroVisualPanel>
    with SingleTickerProviderStateMixin {
  // one AnimationController, repeat(), period ~6-8s
}

class _HeroVisualPainter extends CustomPainter {
  final double t; // 0..1 animation progress, wraps
  // paints: pedestal ellipse glow, light beam cone, N floating orbs,
  // all positions/opacities derived from sin(t*2*pi + phase) — no mutable
  // per-object state, no per-frame Random() calls (unlike _Dot, which
  // mutates position every tick via setState in the parent).
}
```

Perf note: `_NetworkBg` recomputes 40 mutable `_Dot` objects and calls
`setState` every 16ms tick. The hero panel instead derives every visual
value analytically from a single animation value each frame — cheaper, and
avoids adding a second independent 60fps `setState` loop stacked on top of
the existing one when both are visible.

The A'lochi tree logo (`assets/logo.png`) sits centered on the pedestal, tying
the "light beam from a platform" motif to the actual brand mark instead of
being generic.

Accessibility: the whole panel is wrapped in
`Semantics(excludeSemantics: true)` — it's decorative, nothing to announce.

### `login_screen.dart` changes

Only the non-auto-logging `return` inside `build()` (L394–516) changes.
Everything else in the file (imports, `_Dot`/`_NetworkPainter`/`_NetworkBg`,
state fields, `_login`/`_accordion`/`_routeButtons`/`_field`/etc.) is
untouched.

New structure:

```dart
return CallbackShortcuts(
  bindings: { ... },               // unchanged
  child: Focus(
    autofocus: true,
    child: Scaffold(
      body: Stack(
        children: [
          const Positioned.fill(child: ColoredBox(color: Color(0xFFF5F0E8))),
          const Positioned.fill(child: _NetworkBg()),
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 900;
                  final formColumn = _LoginFormColumn(...); // extracted existing Column, unchanged content
                  if (!wide) {
                    return SingleChildScrollView(... child: Center(child: formColumn));
                  }
                  return Row(
                    children: [
                      const Expanded(flex: 2, child: HeroVisualPanel()),
                      Expanded(
                        flex: 3,
                        child: SingleChildScrollView(
                          child: Center(child: formColumn),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
          Positioned(top: 0, left: 0, child: ...),   // _newTestsButton, unchanged
          Positioned(top: 0, right: 0, child: ...),  // _updateBadge, unchanged
        ],
      ),
    ),
  ),
);
```

`_LoginFormColumn` is not a new widget class strictly required — the plan
may keep it as a local `Widget` variable/method (`_formColumn()`) inside
`_LoginScreenState` if that's simpler than extracting a class, as long as
the JSX-equivalent content (logo, title, subtitle, language switcher,
`_routeButtons`, `_accordion`, sync/history row) is reused verbatim in both
the narrow and wide branches — implementer's call, not a hard requirement.

## Error handling / edge cases

- No new error states — this is pure presentation, no network/async calls
  added.
- Window resize across the 900px threshold while the accordion is expanded
  (`_expanded == true`, login form visible): must not lose form state
  (`_userCtrl`/`_passCtrl` text, `_error`) or drop focus destructively.
  Since the same `_accordion()` widget instance content moves between two
  `Row`/`Column` parents via the same build, not two different widget
  subtrees with different keys, this should Just Work — but the
  implementation plan must explicitly verify it (resize while typing, both
  directions) since misplaced `Key`s could cause Flutter to recreate state.
- Very narrow windows (< ~360px): out of scope, already unhandled today,
  not introduced by this change.

## Testing / verification

- `flutter analyze` → 0 errors (project standard, per `flutter-windows`
  skill and `docs/login-redesign/TASK_01...md` precedent).
- Manual verification via `run`/`webapp-testing`-equivalent Flutter desktop
  launch at three window widths: narrow (<900, confirm pixel-identical to
  current behavior), just above threshold (~900-1000, confirm split-panel
  appears and both columns are usable), wide (>1400, confirm hero panel
  doesn't look sparse/empty).
- Resize test: drag window width across the 900px boundary with the
  accordion expanded and text typed into the login fields — confirm no
  state loss (see Edge cases above).
- Confirm `_newTestsButton()` and `_updateBadge()` still sit at the
  Scaffold's top corners, unaffected by the new Row, in both layouts.

## Out of scope

- Student-entry screen (`_buildStudentStep`/step widgets later in the same
  file) — not touched.
- Any change to `_login`, `_accordion` internals, `_routeButtons` internals,
  or auth logic.
- Custom window chrome (the reference mockup's minimize/maximize/close
  icons are just how the mockup image was framed — the app uses the native
  OS title bar today and that isn't changing).
