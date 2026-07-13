# TASK 03 — Verification checklist

**Sonnet implements. Do not commit — lead agent verifies first.**

Run from `/Users/max/PycharmProjects/AlochiSchool/alochi-monitoring-flutter`.

## Static
- [ ] `flutter analyze` → **0 errors** (no "unused element" warnings → all of
      `_wideLayout/_narrowLayout/_leftPanel/_circle/_infoRow/_formPanel` deleted).

## Functional (run the app: `flutter run`)
- [ ] Logo visible inside the white rounded box; title "Alochi Monitoring" + subtitle.
- [ ] Two route buttons render equal width in a Row.
- [ ] "Testlar" button is visually disabled (greyed, ~60% opacity) with an orange
      "Tez kunda" badge top-right; tapping it does **nothing**.
- [ ] Tapping "Alochi Monitoring" toggles the accordion open/closed **smoothly**
      (AnimatedSize), and the button turns orange/white while expanded.
- [ ] Server status dot + text show inside the accordion; "Qayta tekshirish" appears
      only when offline and re-runs the check.
- [ ] Username + password fields work; eye toggle shows/hides the password.
- [ ] Empty-field validation messages appear ("Login kiriting" / "Parol kiriting").
- [ ] Error box shows/hides via AnimatedSize on a failed login.
- [ ] "Kirish" button: shows spinner while loading; logs in (PackageScreen) on success.
      Label/icon reflect online ("Kirish"/arrow) vs offline ("Offline kirish"/wifi-off).
- [ ] "Oddiy kirish" navigates to LocalGradeScreen.
- [ ] Enter key submits the form when the accordion is open.
- [ ] SyncImagesButton + "Oflayn Tarix" (→ HistoryScreen) both accessible in the bottom row.
- [ ] PIN error (TASK 02) reads "Maxfiy parol noto'g'ri" with no hint.

## Then
Report results to the lead agent. **Do not commit** — lead verifies first.
