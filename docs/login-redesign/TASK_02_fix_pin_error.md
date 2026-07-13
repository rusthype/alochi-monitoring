# TASK 02 — Remove PIN hint from local grade error

**File:** `lib/features/local_test/local_grade_screen.dart`
**Line:** 71
**Sonnet implements. Do not commit — lead agent verifies first.**

## Change
```dart
// BEFORE (line 71):
setState(() => _err = "Maxfiy parol noto'g'ri (Maslahat: 1234)");
// AFTER:
setState(() => _err = "Maxfiy parol noto'g'ri");
```
Leak risk: the old string reveals the PIN (`1234`) in the UI. Remove the hint only;
do not change the `!= '1234'` comparison on line 70 or any surrounding logic.

## Verify
- `flutter analyze` → 0 errors.
- Enter a wrong PIN on the Oddiy kirish flow → error reads "Maxfiy parol noto'g'ri"
  with no "(Maslahat: 1234)" suffix.
