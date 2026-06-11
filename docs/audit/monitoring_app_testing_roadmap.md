# Alochi Monitoring App — Testing Roadmap

**App:** `alochi-monitoring-flutter` v1.0.36+36  
**Audit date:** 2026-06-11  
**Starting baseline:** 7 test cases, 0 CI test gates, ~2–5% coverage

---

## Guiding Principles

1. **Fix the data-loss bug (F1) in the same sprint as the first tests** — it is the most
   critical production risk and is directly testable.
2. **Unit tests before widget/E2E** — the most valuable tests here are pure-logic unit tests
   that exercise scoring math and answer remapping. These are cheap, fast, and catch the
   highest-risk bugs.
3. **CI gate first** — before adding more tests, make the existing 7 tests (and new ones)
   actually block releases.
4. **No mocking library today** — add `mocktail` in Week 1; this unlocks testing all HTTP and
   DB paths.
5. **`integration_test/` in Week 3** — only after unit and integration tests cover the logic
   layer; E2E on top of untested logic is expensive and brittle.

---

## Week 1 — CI Gate + Highest-ROI Unit Tests

**Goal:** Unblock the test suite from being completely ignored. Add the minimum tooling. Cover
the three P0 correctness risks (R1, R2, R3) that could silently produce wrong exam scores.

### 1.1 Add `mocktail` to dev dependencies

```yaml
# pubspec.yaml dev_dependencies:
mocktail: ^0.3.0
```

**Why:** All meaningful tests for API calls, DB writes, and connectivity require dependency
injection of a mock. `mocktail` requires no code generation, works with any class.  
**Effort:** 30 min (add dep + verify `flutter pub get`).

---

### 1.2 Add CI test gate to `build-windows.yml`

Add these two steps **before** the `flutter build windows` step:

```yaml
- name: flutter analyze
  run: flutter analyze --no-pub

- name: flutter test
  run: flutter test --coverage
```

**Why:** Currently zero tests run in CI. Any regression ships. This step makes the entire
test suite a merge/release gate.  
**Target file:** `.github/workflows/build-windows.yml`  
**Effort:** 30 min.

---

### 1.3 Unit tests — Offline answer shuffle correctness (R1) ⭐ P0

**Target:** `lib/features/local_test/local_data.dart`, `_shuffleOptions` logic  
**Test file:** `test/local_data_test.dart`

Tests to write:

| Test | Assertion |
|---|---|
| Correct answer remapped correctly after shuffle | After `_shuffleOptions`, `q.correct` == the letter of `q.options` containing the original correct text |
| Options text array length preserved | `q.options.length == 4` after shuffle |
| `optionImages` array stays index-aligned with options | `q.optionImages[i]` corresponds to `q.options[i]` post-shuffle |
| Shuffles are non-deterministic (run 10×, at least one differs) | Shuffle actually randomizes; correct still valid after each run |
| Edge case: correct == 'a', 'b', 'c', 'd' — all remapped | Run 4 variants with each original correct letter |
| Subject `'m'`/`'e'` preserved through shuffle | `q.subject` unchanged after `_shuffleOptions` |

**ROI:** Single highest-value test file. If the Fisher-Yates remap has a bug, these tests
catch it before it silently misgrades every offline student.  
**Effort:** 2–3 hours.

---

### 1.4 Unit tests — Offline scoring math (R2) ⭐ P0

**Target:** `lib/features/local_test/local_test_screen.dart`, `_finish()` scoring loop  
**Test file:** `test/local_scoring_test.dart`

Refactor note: extract `_computeScores(List<LocalQuestion>, Map<int,String>)` as a pure
function before testing — the current logic is embedded in `_finish` inside `StatefulWidget`.

| Test | Assertion |
|---|---|
| 10 correct, 0 wrong → `pct = 100` | `_computeScores` → `totalPct == 100` |
| 0 correct → `pct = 0` | |
| Passing boundary: 6/10 = 60 → `passed == true` | `pct >= 60` |
| Failing boundary: 5/10 = 50 → `passed == false` | |
| Integer division: 7/10 = 70 (not 70.0) | `pct` is `int` |
| Math questions counted by `subject == 'm'` | `mathScore` only counts `'m'` subject |
| English questions counted by `subject == 'e'` | `engScore` only counts `'e'` subject |
| Per-topic accumulation: `topicBreakdown[topic].ok` | Each topic's ok count is correct |
| Mixed question order (not sorted by subject) | Scoring still correct when `'m'`/`'e'` are interleaved |

**Effort:** 3–4 hours (including extracting the pure function).

---

### 1.5 Unit tests — Online answer ID keying (R3) ⭐ P0

**Target:** `lib/features/test/test_screen.dart`, answer-map building in `_finish()`  
**Test file:** `test/online_answer_map_test.dart`

Refactor note: extract `_buildAnswerMap(List<Question>, Map<int,String>)` as a pure function.

| Test | Assertion |
|---|---|
| Answer at index 0 keyed by `questions[0].id` | `map[q0.id] == 'a'` |
| Answer at index N keyed by `questions[N].id` | Works for any position |
| Unanswered questions not included in map | Missing index → key absent |
| 20-question map with all answered → map length == 20 | No extra or missing entries |
| `subject == 'math'` isolation | `isMath` check uses `'math'` correctly |

**Effort:** 2–3 hours (including extracting the pure function).

---

### 1.6 Unit tests — `fixImageUrl` edge cases

**Target:** `lib/core/api/api_client.dart`, `fixImageUrl`  
**Target file:** Extend existing `test/api_client_test.dart`

| Test | Assertion |
|---|---|
| `http://` URL not converted to `https://` | `http://` passed through as-is (or document intended behaviour) |
| URL with fragment `#anchor` | Fragment preserved or stripped per spec |
| URL with no path after host (`https://api.alochi.org`) | Does not crash; returns valid URL |
| Non-ASCII characters in path | Percent-encoded correctly |

**Effort:** 1 hour.

---

### 1.7 Unit tests — `checkOnlineWithRetry` edge cases

**Target:** `lib/features/auth/login_screen.dart`, `checkOnlineWithRetry`  
**Target file:** Extend existing `test/login_online_check_test.dart`

| Test | Assertion |
|---|---|
| Ping callback times out → returns `false` | `onTimeout: () => false` branch hit |
| Ping throws exception → returns `false` | `catch (_) => false` branch |
| Custom `attempts = 1` → only 1 attempt | Loop respects the parameter |
| Custom `retryDelay = Duration(milliseconds: 10)` | Non-zero delay doesn't block indefinitely |

**Effort:** 1 hour.

---

### Week 1 Summary

| Item | Hours | Blocks |
|---|---|---|
| Add `mocktail` | 0.5 | Week 2 integration tests |
| CI `flutter analyze` + `flutter test` | 0.5 | Every future PR |
| R1: offline answer shuffle tests | 3 | P0 scoring correctness |
| R2: offline scoring math tests | 4 | P0 scoring correctness |
| R3: online answer map tests | 3 | P0 scoring correctness |
| `fixImageUrl` edge cases | 1 | P2 cleanup |
| `checkOnlineWithRetry` edge cases | 1 | P2 cleanup |
| **Total** | **~13 hours** | |

---

## Week 2 — Integration Tests (Mocked Boundaries)

**Goal:** Test the integration layers: API client, offline queue, sync service, credential
cache, history DB. These use real logic with mocked external dependencies (HTTP, SQLite in
in-memory mode).

### 2.1 `MonitoringApi` HTTP paths

**Target:** `lib/core/api/api_client.dart`  
**Test file:** `test/api_client_http_test.dart`  
**Approach:** Mock `http.Client` via `mocktail` (`MockClient`). Inject into `MonitoringApi`
constructor (requires a small refactor to accept an optional `http.Client` parameter).

| Test | Covers |
|---|---|
| `login` 200 → `StudentSession` populated | Happy path |
| `login` 400 → `ApiException(400, ...)` | Wrong credentials |
| `login` 429 → `ApiException(429, ...)` | Rate limit |
| `login` network timeout → `ApiException(0, ...)` | Transport failure |
| `getPackages` 200 → `List<TestPackage>` | F2: should not crash on valid JSON |
| `getPackages` 200 malformed JSON → wrapped exception (F2) | Currently crashes with raw `FormatException` |
| `getQuestions` 200 → `List<Question>` | |
| `submitResultFull` 201 + scores → `{synced:true, math_score:N}` | |
| `submitResultFull` 409 → `{synced:true}` | Idempotency |
| `submitResultFull` 500 → `{synced:false}` (no crash) (F3) | Silent swallow |
| `submitResultFull` network fail → `{synced:false}` | |
| `submitResultFull` token == null → no Bearer header sent | Precondition for F1 fix |
| `submitLocalResult` 200 → `true`, `Idempotency-Key` header present | |
| `submitLocalResult` 400 → `false` | |

**Effort:** 4–5 hours.

---

### 2.2 `OfflineQueue` SQLite

**Target:** `lib/core/db/offline_queue.dart`  
**Test file:** `test/offline_queue_test.dart`  
**Approach:** Use `sqflite_common_ffi` with `inMemoryDatabaseFactory` for tests (no file I/O).

| Test | Covers |
|---|---|
| `enqueue` → row in `queue` table with correct payload | Enqueue |
| `enqueueLocal` → row in `local_queue` with token | Enqueue local |
| `flush` success → row deleted | Happy path |
| `flush` failure → `attempts` incremented, row remains | Network failure |
| `flush` → 10 attempts → row still present (purgeStale deletes it) | Attempt cap |
| `flushLocal` → `Idempotency-Key` token preserved from row (not regenerated) (F6) | Idempotency regression |
| `flushLocal` → null token in DB → new token generated, row updated before submit | F6 edge case |
| `purgeStale` → removes rows with `attempts >= 10` | Stale purge |
| `purgeStale` → removes rows older than 7 days | Stale purge |
| `purgeStale` → does NOT remove a valid new row | No over-deletion |
| Schema migration v1→v4 on existing DB | Migration correctness |

**Effort:** 4–5 hours.

---

### 2.3 `SyncService` logic

**Target:** `lib/core/sync/sync_service.dart`  
**Test file:** `test/sync_service_test.dart`  
**Approach:** Mock `MonitoringApi` (inject via constructor). Mock `OfflineQueue.pendingCount`.

| Test | Covers |
|---|---|
| Reentrancy guard: second `_flushAll` while first in progress → skipped | `_flushing` |
| Empty queue → no `api.ping()` call | Short-circuit |
| Non-empty queue + `ping` false → no flush | Ping guard |
| Non-empty queue + `ping` true → `flushOfflineQueue` called | Happy path |
| `flushNow()` with `_token == null` → queue NOT flushed (F1 fix) | Token guard (CURRENTLY ABSENT) |
| Connectivity-change event triggers `_flushAll` | Event binding |
| 60s timer triggers `_flushAll` | Timer |

**Effort:** 3–4 hours (plus the F1 code fix it validates).

---

### 2.4 `CredentialCache` round-trip

**Target:** `lib/core/db/credential_cache.dart`  
**Test file:** `test/credential_cache_test.dart`  
**Approach:** Use `FlutterSecureStorage` mock from `flutter_secure_storage`'s test helpers
(the package provides `FlutterSecureStoragePlatform.instance = InMemoryPlugin()`).

| Test | Covers |
|---|---|
| `saveCredentials` + `saveSession` → `loadOfflineSession` success | Happy path |
| `loadOfflineSession` wrong username → returns null | Credential mismatch |
| `loadOfflineSession` wrong password → returns null | Credential mismatch (F8 check) |
| `loadOfflineSession` with missing stored session fields → returns null | Partial data |
| `loadCredentials` → correct username/password prefilled | Form prefill |
| `clear()` called → subsequent `loadOfflineSession` returns null | Logout (F7 — currently no caller) |

**Effort:** 3 hours.

---

### 2.5 `HistoryDb` round-trip

**Target:** `lib/core/db/history_db.dart`  
**Test file:** `test/history_db_test.dart`  

| Test | Covers |
|---|---|
| `insertResult` → `getHistory` returns the row | Round-trip |
| Multiple inserts → ordered `date_taken DESC` | Sort order |
| `clearHistory` → `getHistory` returns empty | Delete |
| `insertResult` with minimal fields → no crash | Edge case |

**Effort:** 2 hours.

---

### Week 2 Summary

| Item | Hours |
|---|---|
| `MonitoringApi` HTTP tests | 5 |
| `OfflineQueue` SQLite tests | 5 |
| `SyncService` logic tests | 4 |
| `CredentialCache` tests | 3 |
| `HistoryDb` tests | 2 |
| **Total** | **~19 hours** |

---

## Week 3 — End-to-End Integration Tests

**Goal:** Verify the complete exam-taking flows using `integration_test/` package with real
Flutter widget rendering and navigation. Mock only the network boundary.

### Setup

Add `integration_test` to `pubspec.yaml`:

```yaml
dev_dependencies:
  integration_test:
    sdk: flutter
```

Create `integration_test/` directory. Create a mock HTTP client fixture that can be injected
into `MonitoringApi` for all integration tests.

### 3.1 Online exam flow (E2E-1)

**File:** `integration_test/online_exam_test.dart`

Steps:
1. Launch app with mock API responding to all endpoints.
2. Enter credentials → verify `POST /auth/login/` → `PackageScreen` appears with packages.
3. Tap first package → `ConfirmScreen` shows correct student name and question count.
4. Tap "Start" → `TestScreen` shows first question (Math, 30-min timer visible).
5. Answer all 10 Math + 10 English questions via keyboard simulation (`A`–`D`).
6. Verify auto-submit or manual submit sends `POST /results/` with correct `answers` map.
7. `ResultScreen` shows correct `totalPct` from mock server response.
8. Tap "Keyingi talaba" → `LoginScreen` shown with empty form.

**Assertions:** Answer map key is `question.id`; `totalPct` from server rendered correctly;
navigation stack cleared; `api.clearToken()` called after "next student".

**Effort:** 5 hours.

---

### 3.2 Offline (guest) exam flow (E2E-2)

**File:** `integration_test/local_exam_test.dart`

Steps:
1. Launch app.
2. Tap "Oddiy kirish" → grade wizard appears.
3. Select grade 2, variant 3.
4. Enter name "Test Student", PIN `1234`.
5. `LocalTestScreen` appears with 20 questions from `assets/questions.json`.
6. Answer all questions. Verify each correct answer (using known answers from JSON).
7. `LocalResultScreen` shows expected `pct` (computed from known answers).
8. Verify `HistoryDb` contains the result row.
9. Verify `OfflineQueue.local_queue` contains one row with an idempotency token.
10. Tap "Keyingi o'quvchi" → `LocalGradeScreen` shown.

**Assertions:** `pct` matches expected value from known-answer fixture; DB rows present;
idempotency token non-null and consistent between enqueue and flush.

**Effort:** 5–6 hours.

---

### 3.3 Offline result syncs on reconnect (E2E-3)

**File:** `integration_test/sync_on_reconnect_test.dart`

Steps:
1. Complete local exam while mock API returns network error.
2. Result queued; `flushNow()` fails silently.
3. Simulate connectivity restored (mock connectivity_plus).
4. `SyncService` triggers → `POST /result/` succeeds (mock 200).
5. `local_queue` row deleted.
6. Run again — second flush → 409 → row still deleted (idempotent success).

**Assertions:** Single server call on first flush; 409 not duplicated to history; queue empty
after success.

**Effort:** 4 hours.

---

### 3.4 Wrong PIN rejected (LocalGradeScreen)

**File:** `integration_test/local_exam_test.dart` (extend)

Steps:
1. Enter PIN `9999` → error message shown.
2. Enter PIN `1234` → proceeds normally.

**Assertions:** Wrong PIN shows "Noto'g'ri PIN" message; correct PIN proceeds.  
**Effort:** 1 hour.

---

### Week 3 Summary

| Item | Hours |
|---|---|
| Online exam E2E | 5 |
| Offline (guest) exam E2E | 6 |
| Sync-on-reconnect E2E | 4 |
| PIN validation | 1 |
| Test infra/fixtures setup | 3 |
| **Total** | **~19 hours** |

---

## Week 4 — Regression Suite + Coverage Gate

**Goal:** Add visual regression (golden) tests for scored result screens, add PDF smoke test,
tighten CI, set coverage floor.

### 4.1 Golden tests — `ResultScreen`

**File:** `test/goldens/result_screen_golden_test.dart`  
**Tooling:** Use `flutter_test`'s built-in `matchesGoldenFile` (no extra package needed).

| Golden test | Scenario |
|---|---|
| `result_90pct_pass.png` | Score 90%, passed, all sections strong |
| `result_60pct_pass.png` | Score 60%, exactly passing threshold |
| `result_55pct_fail.png` | Score 55%, failing state |
| `result_0_wrong_answers.png` | Perfect score — wrong-answers section empty |

**Effort:** 3 hours (initial generation + CI step to regenerate on `--update-goldens`).

---

### 4.2 Golden tests — `LocalResultScreen`

Same pattern as above. 2 hours.

---

### 4.3 PDF generation smoke test

**File:** `test/pdf_service_test.dart`

| Test | Assertion |
|---|---|
| `PdfService.generateResultPdf` returns non-null `Uint8List` | No crash |
| PDF byte size > 5,000 bytes | Non-trivial output |
| Font asset loads without throwing | F11 regression |
| `PdfReport.generate` with mock image URLs (0 images) → file created | Minimal offline case |

**Effort:** 2 hours.

---

### 4.4 Tighten `analysis_options.yaml`

```yaml
linter:
  rules:
    avoid_print: true
    prefer_const_constructors: true
    prefer_final_fields: true
    prefer_final_locals: true
    always_declare_return_types: true
    unawaited_futures: true

analyzer:
  language:
    strict-casts: true
    strict-raw-types: true
  errors:
    avoid_print: error
```

**Effort:** 1 hour (fix any new lint failures).

---

### 4.5 Coverage threshold in CI

```yaml
- name: flutter test --coverage
  run: flutter test --coverage

- name: Check coverage threshold
  run: |
    total=$(lcov --summary coverage/lcov.info 2>&1 | grep -E 'lines' | awk '{print $2}' | tr -d '%')
    if (( $(echo "$total < 40" | bc -l) )); then
      echo "Coverage $total% is below threshold 40%"
      exit 1
    fi
```

**Effort:** 1 hour. Target: ≥40% line coverage after Weeks 1–3.

---

### 4.6 Replace trivial smoke test

Replace `test/widget_test.dart` with a meaningful login screen widget test:

```dart
testWidgets('Login screen renders form elements', (tester) async {
  await tester.pumpWidget(AlochiMonitoringApp());
  await tester.pumpAndSettle();
  expect(find.byType(TextField), findsNWidgets(2)); // username + password
  expect(find.text('Kirish'), findsOneWidget);
  expect(find.text('Oddiy kirish'), findsOneWidget);
});
```

**Effort:** 1 hour.

---

### Week 4 Summary

| Item | Hours |
|---|---|
| Golden tests (ResultScreen + LocalResultScreen) | 5 |
| PDF smoke test | 2 |
| `analysis_options.yaml` tightening | 1 |
| Coverage gate in CI | 1 |
| Replace widget smoke test | 1 |
| **Total** | **~10 hours** |

---

## Roadmap at a Glance

| Week | Focus | Est. Hours | Coverage After |
|---|---|---|---|
| 1 | CI gate + P0 unit tests (R1, R2, R3) + tooling | 13 | ~25% |
| 2 | Integration tests (API, queue, sync, cache, DB) | 19 | ~45% |
| 3 | E2E integration tests (3 full flows) | 19 | ~55% |
| 4 | Golden + PDF + lint + coverage gate | 10 | ~60% |
| **Total** | | **~61 hours** | **~60%** |

### Prioritized by ROI

If only 1 week of time is available, prioritize in this order:

1. **CI `flutter test`/`flutter analyze` gate** (30 min, blocks all regressions from shipping)
2. **R1: Offline answer shuffle tests** (3 hours, P0 correctness)
3. **R2: Offline scoring tests** (4 hours, P0 correctness)
4. **F1: Token-restore-at-startup** (1 hour code fix + 1 hour test, P0 data loss)
5. **R3: Online answer ID keying** (3 hours, P0 correctness)

These 5 items (~12 hours) address every BLOCKER-rated release risk and directly test the three
highest-risk business logic paths in the app.
