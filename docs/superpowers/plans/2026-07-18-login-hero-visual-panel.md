# Login Split-Panel Hero Visual Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** On wide windows (≥900px), show the login screen as a split panel — a new decorative, animated "hero visual" on the left and the existing login card on the right — while leaving narrow-window behavior pixel-identical to today.

**Architecture:** A new self-contained `HeroVisualPanel` widget (own file, own `CustomPainter`, zero external dependencies) renders a brand-colored pseudo-3D glow/beam/floating-orbs animation. `login_screen.dart`'s `build()` gets a `LayoutBuilder` that either renders today's single-column layout unchanged (narrow) or a `Row` of `HeroVisualPanel` + the same form content (wide). The existing form content (logo, title, `_routeButtons`, `_accordion`, sync/history row) is extracted into one reused `_formColumn()` method so both branches render identical content.

**Tech Stack:** Flutter 3.41 desktop app (`alochi_monitoring`), Dart 3.11, no new packages.

**Spec:** `docs/superpowers/specs/2026-07-18-login-hero-visual-panel-design.md`

---

## Task 1: `HeroVisualPanel` widget (TDD)

**Files:**
- Create: `lib/features/auth/widgets/hero_visual_panel.dart`
- Test: `test/hero_visual_panel_test.dart`

This is a purely decorative widget with no dependency on `_LoginScreenState` — build and test it standalone first.

- [ ] **Step 1: Write the failing test**

Create `test/hero_visual_panel_test.dart`:

```dart
import 'package:alochi_monitoring/features/auth/widgets/hero_visual_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('HeroVisualPanel renders and animates without throwing',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
            width: 400, height: 600, child: HeroVisualPanel()),
      ),
    );

    expect(find.byType(CustomPaint), findsWidgets);

    // Advance through more than one full 7s animation loop.
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(seconds: 3));

    expect(tester.takeException(), isNull);
  });

  testWidgets('HeroVisualPanel excludes itself from the semantics tree',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
            width: 400, height: 600, child: HeroVisualPanel()),
      ),
    );

    final semanticsWidget = tester.widget<Semantics>(
      find
          .descendant(
            of: find.byType(HeroVisualPanel),
            matching: find.byType(Semantics),
          )
          .first,
    );

    expect(semanticsWidget.excludeSemantics, isTrue);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/hero_visual_panel_test.dart`
Expected: FAIL — `Error: Target of URI doesn't exist: 'package:alochi_monitoring/features/auth/widgets/hero_visual_panel.dart'` (the file doesn't exist yet).

- [ ] **Step 3: Write the implementation**

Create `lib/features/auth/widgets/hero_visual_panel.dart`:

```dart
// lib/features/auth/widgets/hero_visual_panel.dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';

/// Purely decorative animated visual for the login screen's wide-window
/// split-panel layout. Has no external state and no interaction.
class HeroVisualPanel extends StatefulWidget {
  const HeroVisualPanel({super.key});

  @override
  State<HeroVisualPanel> createState() => _HeroVisualPanelState();
}

class _HeroVisualPanelState extends State<HeroVisualPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.bg,
              AppColors.brand.withValues(alpha: 0.06),
            ],
          ),
        ),
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (context, _) => CustomPaint(
            painter: _HeroVisualPainter(_ctrl.value),
            size: Size.infinite,
          ),
        ),
      ),
    );
  }
}

class _OrbSpec {
  final double dx; // fractional horizontal position, 0..1
  final double size;
  final double phase; // 0..1, staggers the loop start
  final Color color;

  const _OrbSpec({
    required this.dx,
    required this.size,
    required this.phase,
    required this.color,
  });
}

const List<_OrbSpec> _orbSpecs = [
  _OrbSpec(dx: 0.20, size: 14, phase: 0.00, color: AppColors.brand),
  _OrbSpec(dx: 0.75, size: 10, phase: 0.15, color: Color(0xFF0D9488)),
  _OrbSpec(dx: 0.35, size: 18, phase: 0.30, color: AppColors.brand),
  _OrbSpec(dx: 0.60, size: 8, phase: 0.45, color: Color(0xFF4A90D9)),
  _OrbSpec(dx: 0.85, size: 12, phase: 0.60, color: AppColors.brand),
  _OrbSpec(dx: 0.10, size: 9, phase: 0.72, color: Color(0xFF0D9488)),
  _OrbSpec(dx: 0.50, size: 16, phase: 0.85, color: AppColors.brand),
  _OrbSpec(dx: 0.28, size: 11, phase: 0.05, color: Color(0xFF4A90D9)),
  _OrbSpec(dx: 0.68, size: 13, phase: 0.55, color: AppColors.brand),
];

class _HeroVisualPainter extends CustomPainter {
  final double t;
  const _HeroVisualPainter(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final pedestalCenter = Offset(size.width * 0.5, size.height * 0.82);
    final pulse = 0.9 + 0.1 * math.sin(t * 2 * math.pi);

    // Ambient glow behind everything.
    final glowRadius = math.min(size.width, size.height) * 0.65;
    canvas.drawCircle(
      pedestalCenter,
      glowRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.brand.withValues(alpha: 0.16),
            AppColors.brand.withValues(alpha: 0.0),
          ],
        ).createShader(
            Rect.fromCircle(center: pedestalCenter, radius: glowRadius)),
    );

    // Light beam rising from the pedestal.
    final beamAlpha = 0.12 + 0.08 * math.sin(t * 2 * math.pi + math.pi / 3);
    final beamTopY = size.height * 0.05;
    final beamPath = Path()
      ..moveTo(pedestalCenter.dx - size.width * 0.14, pedestalCenter.dy)
      ..lineTo(pedestalCenter.dx - size.width * 0.02, beamTopY)
      ..lineTo(pedestalCenter.dx + size.width * 0.02, beamTopY)
      ..lineTo(pedestalCenter.dx + size.width * 0.14, pedestalCenter.dy)
      ..close();
    canvas.drawPath(
      beamPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            AppColors.brand.withValues(alpha: beamAlpha),
            AppColors.brand.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromLTWH(
            0, beamTopY, size.width, pedestalCenter.dy - beamTopY)),
    );

    // Pedestal disc.
    final pedestalRect = Rect.fromCenter(
      center: pedestalCenter,
      width: size.width * 0.34,
      height: size.height * 0.035,
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: pedestalCenter,
        width: pedestalRect.width * pulse,
        height: pedestalRect.height * pulse,
      ),
      Paint()
        ..shader = RadialGradient(colors: [
          AppColors.brand.withValues(alpha: 0.55),
          AppColors.brand.withValues(alpha: 0.0),
        ]).createShader(pedestalRect),
    );

    // Floating orbs: analytic position from a single animation value `t`,
    // no mutable per-object state (unlike _NetworkBg's _Dot list).
    for (final orb in _orbSpecs) {
      final progress = (t + orb.phase) % 1.0;
      final dy = 1.0 - progress; // bottom (1.0) -> top (0.0) over the loop
      final opacity = math.sin(math.pi * progress).clamp(0.0, 1.0);
      final sway =
          0.03 * math.sin(2 * math.pi * progress * 2 + orb.phase * 10);
      final center = Offset(
        size.width * (orb.dx + sway),
        size.height * (0.10 + dy * 0.75),
      );
      canvas.drawCircle(
        center,
        orb.size,
        Paint()
          ..color = orb.color.withValues(alpha: 0.45 * opacity)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, orb.size * 0.6),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _HeroVisualPainter oldDelegate) =>
      oldDelegate.t != t;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/hero_visual_panel_test.dart`
Expected: `00:0X +2: All tests passed!`

- [ ] **Step 5: Analyze**

Run: `flutter analyze lib/features/auth/widgets/hero_visual_panel.dart`
Expected: `No issues found!`

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/widgets/hero_visual_panel.dart test/hero_visual_panel_test.dart
git commit -m "feat(auth): add animated hero visual panel for wide login layout"
```

---

## Task 2: Extract `_formColumn()` in `login_screen.dart`

**Files:**
- Modify: `lib/features/auth/login_screen.dart`

Pure refactor — move the existing form `Column` (today at lines 417–486,
inside the `ConstrainedBox` at line 415) into its own method with no
content changes, so Task 3 can reuse it in two branches. No behavior
change, so no new test; verified by `flutter analyze` + the existing suite
staying green.

- [ ] **Step 1: Read the current block to copy exactly**

Run: `sed -n '408,491p' lib/features/auth/login_screen.dart`

Confirm it matches (logo box → title → subtitle → language switcher →
`_routeButtons(isSmall)` → `_accordion()` → sync/history row) before
proceeding — if it doesn't match (file has changed since this plan was
written), stop and reconcile before continuing.

- [ ] **Step 2: Add the `_formColumn` method**

Insert immediately after the `build()` method closes (today: right before
`Widget _newTestsButton()`, i.e. after the line `  }` that closes `build()`
around line 517):

```dart
  Widget _formColumn(AppLocalizations l10n, bool isSmall) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Logo in white rounded box
        Center(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.border),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .10),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Image.asset('assets/logo.png',
                width: 56, height: 56, fit: BoxFit.contain),
          ),
        ),
        const SizedBox(height: 18),
        Text(l10n.appTitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.titleLarge
                .copyWith(fontWeight: FontWeight.w800)),
        const SizedBox(height: 4),
        Text(l10n.appSubtitle,
            textAlign: TextAlign.center,
            style: AppTextStyles.bodyMedium
                .copyWith(color: AppColors.ink2)),
        const SizedBox(height: 24),
        const Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: EdgeInsets.only(bottom: 8.0, right: 4.0),
            child: LanguageSwitcher(),
          ),
        ),
        _routeButtons(isSmall),
        _accordion(),
        const SizedBox(height: 16),
        // Bottom row: sync + history
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 4,
          runSpacing: 4,
          children: [
            const SyncImagesButton(),
            TextButton.icon(
              onPressed: () => context.push('/history', extra: {}),
              icon: const Icon(Icons.history_rounded, size: 16),
              label: Text(l10n.offlineHistory),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.ink2,
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    );
  }
```

- [ ] **Step 3: Replace the inline Column with a call to `_formColumn`**

In `build()`, replace (today's lines 415–486, the `ConstrainedBox` and
everything inside it):

```dart
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            // ... (all the children listed in Step 2)
                          ],
                        ),
                      ),
```

with:

```dart
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _formColumn(l10n, isSmall),
                      ),
```

Everything outside this (`Positioned.fill` → `SafeArea` → `SingleChildScrollView`
→ `Align(topCenter)`, and the two corner `Positioned` buttons after it)
stays untouched in this task.

- [ ] **Step 4: Analyze**

Run: `flutter analyze lib/features/auth/login_screen.dart`
Expected: `No issues found!`

- [ ] **Step 5: Run the full test suite**

Run: `flutter test`
Expected: all existing tests still pass (this is a pure code move — if
anything fails, the extraction introduced a behavior change; fix before
proceeding).

- [ ] **Step 6: Commit**

```bash
git add lib/features/auth/login_screen.dart
git commit -m "refactor(auth): extract login form column into _formColumn()"
```

---

## Task 3: Wide-window split-panel layout

**Files:**
- Modify: `lib/features/auth/login_screen.dart`

- [ ] **Step 1: Import the new widget**

Add near the other relative feature imports (after
`import '../local_test/sync_images_button.dart';`):

```dart
import 'widgets/hero_visual_panel.dart';
```

- [ ] **Step 2: Replace the `Positioned.fill` content wrapper with a `LayoutBuilder`**

Replace (the block introduced/left alone by Task 2 — starts at
`Positioned.fill(` right after `const Positioned.fill(child: _NetworkBg()),`
and ends at the `),` that closes it, right before the `Positioned(top: 0,
left: 0, ...)` block for `_newTestsButton()`):

```dart
              Positioned.fill(
                child: SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 32),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _formColumn(l10n, isSmall),
                      ),
                    ),
                  ),
                ),
              ),
```

with:

```dart
              Positioned.fill(
                child: SafeArea(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      final formColumn = ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 480),
                        child: _formColumn(l10n, isSmall),
                      );
                      if (!wide) {
                        return SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 32),
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: formColumn,
                          ),
                        );
                      }
                      return Row(
                        children: [
                          const Expanded(flex: 2, child: HeroVisualPanel()),
                          Expanded(
                            flex: 3,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 32),
                              child: Center(child: formColumn),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
```

- [ ] **Step 3: Analyze**

Run: `flutter analyze lib/features/auth/login_screen.dart`
Expected: `No issues found!`

- [ ] **Step 4: Run the full test suite**

Run: `flutter test`
Expected: all tests still pass.

- [ ] **Step 5: Commit**

```bash
git add lib/features/auth/login_screen.dart
git commit -m "feat(auth): split-panel login layout with hero visual on wide windows"
```

---

## Task 4: Manual verification

No further code changes in this task — only checks. This covers the
spec's "Testing / verification" and "Edge cases" sections, which are
visual/interactive and not meaningfully automatable given this screen's
dependencies (live API ping, Riverpod providers, go_router, localization).

**Files:** none.

- [ ] **Step 1: Full-project analyze**

Run: `flutter analyze`
Expected: `No issues found!` (no new warnings anywhere in the project).

- [ ] **Step 2: Full test suite**

Run: `flutter test`
Expected: all tests pass, including `test/hero_visual_panel_test.dart` and
`test/login_online_check_test.dart`.

- [ ] **Step 3: Enable macOS desktop target (one-time, if not already enabled)**

Run: `flutter config --enable-macos-desktop`

- [ ] **Step 4: Launch the app on macOS desktop**

Run: `flutter run -d macos`

- [ ] **Step 5: Narrow-window check**

Resize the app window to under 900px wide. Confirm it looks exactly like
the app did before this change: single centered column, dotted network
background, no split panel, no visible hero visual.

- [ ] **Step 6: Wide-window check**

Resize the app window to 1000–1200px wide. Confirm: a left panel shows the
animated glow/beam/floating orbs in the app's orange brand tone (not
purple, not green); a right panel shows the same login card content
(logo, title, buttons, form) as the narrow layout; both `_newTestsButton()`
("Maktablar"/"Школы", top-left) and the update badge (top-right, if a
pending update exists) still sit at the screen's corners, unaffected by
the new `Row`.

- [ ] **Step 7: Very-wide-window check**

Resize to over 1400px wide. Confirm the hero visual still looks
intentional and doesn't look sparse or empty (the ambient glow + beam +
orbs should scale with the panel).

- [ ] **Step 8: Resize-while-typing check**

At a width just below 900px, tap the "Alochi Monitoring" route button to
expand the accordion, type into the Login and Parol fields. While focus is
still in a field, resize the window across the 900px boundary in both
directions. Confirm: the typed text is not lost, the field does not lose
focus destructively, and no exception appears in the terminal running
`flutter run`.

- [ ] **Step 9: Record the result**

If all checks pass, note it in the PR/commit description. If any check
fails, fix the underlying issue in `login_screen.dart` or
`hero_visual_panel.dart`, re-run `flutter analyze` and `flutter test`, and
repeat the relevant manual check before committing the fix.
