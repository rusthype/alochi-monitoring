# Alochi Monitoring App — Risk Assessment

**App:** `alochi-monitoring-flutter` v1.0.36+36  
**Audit date:** 2026-06-11  
**Scope:** Critical business flows, integration risks, E2E candidates, release blockers

---

## Phase 4 — Critical Business Flows (P0 / P1 / P2)

### P0 — Catastrophic if broken

#### P0-1: Offline answer correctness (Local exam flow)

**Why important:** The offline (guest) exam path is the primary use case in schools with
unreliable internet. Thousands of students take these tests. A bug in the answer-option shuffle
or correct-answer remapping silently produces wrong grades for every student.

**Current coverage:** NONE. The shuffle logic in `local_data.dart:41-64` and scoring in
`local_test_screen.dart:159-175` have **zero tests**.

**Failure impact:** Students receive incorrect pass/fail results. This directly affects school
performance records and potentially student progression decisions. The failure would be
invisible until a human noticed a pattern of suspiciously high/low scores across an entire
school.

**Code path:**  
`LocalGradeScreen._startTest()` → `LocalQuestionsLoader.get(grade, variant)` →
`_shuffleOptions` (Fisher-Yates, answer remapping `local_data.dart:57`) →
`LocalTestScreen._finish()` (scoring loop `local_test_screen.dart:159-175`).

---

#### P0-2: Online answer-to-server correctness

**Why important:** The online exam submits student answers to the server for scoring. The
answers map is built by keying student responses against **`question.id`** (not index). Any
off-by-one between the `_answers` Map (index-keyed) and `questions` list would silently send
the wrong letter for each question — the server grades the wrong answers and the student gets
a wrong score with no indication anything went wrong.

**Current coverage:** NONE. `test_screen.dart:186-191` is untested.

**Failure impact:** Server produces a plausible-looking but wrong score. Student sees a wrong
result; wrong answer is potentially recorded on the server. A subtle change in question
ordering from the server could trigger this silently.

**Code path:**  
`ConfirmScreen._start()` → `api.getQuestions(package.id, session.variant)` →
`TestScreen._finish()` → `answersMap[questions[i].id] = _answers[i]` (`:186-191`) →
`api.submitResultFull(result)`.

---

#### P0-3: Completed exam results lost after app restart (F1)

**Why important:** A student completes an online exam, the network fails during submission, and
the result is queued in `monitoring_queue.db`. On app restart, `SyncService.instance.start()`
begins immediately in `main()` — **but the API token is never restored**. When the sync service
attempts to flush the `queue` table with a `null` token, the server returns 401. The `attempts`
counter increments each retry until the row is deleted at 10 attempts or 7 days.

**Current coverage:** NONE. This is a data-integrity bug with zero test detection.

**Failure impact:** A student's completed exam is permanently lost. The student must retake the
exam. No error is shown to any user; the failure only appears in `debugPrint` output.

**Code path:**  
`main.dart:26` `SyncService.instance.start()` → (60s later) `SyncService._flushAll()` →
`api.flushOfflineQueue()` → `OfflineQueue.flush(api.submitResultFull)` →
`submitResultFull` with `_token == null` → `POST /results/` → server 401 →
`ApiException` → `attempts++` → eventually `purgeStale` deletes row.

---

### P1 — High impact

#### P1-1: Offline results duplicated on server (F6)

**Why important:** `OfflineQueue.flushLocal()` reads the idempotency token from the DB row.
If the stored `token` column is null (can happen if a v3→v4 migration produced a null value),
a new UUID is generated (`offline_queue.dart:139`). The server receives the same result with a
different idempotency key and records it as a new result — the student appears to have taken
the test twice.

**Current coverage:** NONE.

**Failure impact:** Inflated student statistics, double-counted results in school analytics.

---

#### P1-2: App crashes on malformed server response (F2)

**Why important:** `MonitoringApi._get()` calls `jsonDecode(resp.body)` after any 2xx response
without a `try/catch` (`api_client.dart:124`). If the server returns a 200 with a malformed
body (e.g. partial HTML error page, proxy interception), this throws a raw `FormatException`
that propagates unhandled to the calling screen. The callers `getPackages` and `getQuestions`
do not catch it. The user sees an unhandled exception crash or a confusing error widget.

**Current coverage:** NONE.

**Failure impact:** Students see unexplained crashes at the package selection or question
loading stage, with no actionable message.

---

#### P1-3: Online exam result enqueued with zero scores (R4)

**Why important:** When an online test submission fails and falls to `OfflineQueue.enqueue`,
the `TestResult` in the queue has `mathScore=0, engScore=0, totalPct=0` (comment:
"server computes the score"). When the row is later flushed, whether the server correctly
re-scores a retry submission has not been verified. If the server requires idempotency and
treats the retry as a duplicate, it returns 409 (treated as `synced:true`) but may use the
original 0/0/0 payload instead of re-scoring.

**Current coverage:** NONE. The interaction between retry, server idempotency, and score
recomputation is entirely unverified.

**Failure impact:** Student receives a 0% score after network recovery, potentially causing
distress and requiring manual admin correction.

---

#### P1-4: Section timer corruption from non-math-first question order (R5)

**Why important:** `TestScreen` assumes the server returns all Math questions before English
questions (`test_screen.dart:41-51`). The 30-minute math timer resets to a 40-minute English
timer only when the current question index advances past `_mathCount`. If the server returns
questions in a different order (or adds a mixed section in a future API update), the section
display ("01/20 Matematika") and both timers will be incorrect. Students in the wrong section
will have wrong time limits.

**Current coverage:** NONE.

**Failure impact:** Students complete the wrong section within the wrong time limit. Scores
may be unfairly penalized.

---

### P2 — Medium risk

| Flow | Current Coverage | Failure Impact |
|---|---|---|
| No idempotency on authenticated result flush (R6) | ❌ | Online exam recorded twice if network fails mid-POST |
| `'math'`/`'english'`/`'m'`/`'e'` subject string inconsistency (R7) | ❌ | Wrong-answer breakdown silently shows 0 in one section |
| Stale token reused after offline login (F8) | ❌ | Subsequent online requests may 401 silently |
| No credential `clear()` on logout (F7) | ❌ | Password persists between users on shared kiosk |
| TLS bypass for image fetches (F10) | ❌ | MITM can inject arbitrary images on untrusted networks |
| Background sync error not surfaced (F9) | ❌ | Silent result loss with no user feedback |
| PDF font asset unguarded (F11) | ❌ | PDF generation crash if font asset missing from bundle |

---

## Phase 5 — Integration Audit

| Dependency | Failure Mode | Current Tests | Missing Tests |
|---|---|---|---|
| `POST /auth/login/` | 400 → short-circuit (correct); 5xx → falls to offline (intended); network down → offline | ❌ | Unit: mock HTTP 400, 429, 500, timeout; integration: full login round-trip |
| `GET /packages/` | Network/API error → `_error` state; malformed 2xx → `FormatException` crash (F2) | ❌ | Unit: mock success + error; test F2 malformed body |
| `GET /packages/{id}/questions/` | Same as above; empty questions list → `TestScreen` launched with 0 questions | ❌ | Unit: empty list, malformed, correct payload |
| `POST /results/` | Server error → `{synced:false}` swallowed (F3); 409 → treated as synced | ❌ | Unit: mock 201 with scores, 409, 5xx, network fail, token-less 401 |
| `GET /my-results/{id}/` | Any failure → `[]` (F4) | ❌ | Unit: mock empty, malformed, network fail |
| `POST /result/` (guest) | Non-2xx → `false`; idempotency key attached | ❌ | Unit: idempotency header present, 2xx success, 4xx fail |
| `OfflineQueue` (SQLite) | DB open failure unhandled; malformed row never cleared by attempts (F5) | ❌ | Integration: enqueue→flush success, failure→attempts++, malformed→7day-age |
| `HistoryDb` (SQLite) | `getHistory`/`clearHistory` errors not caught at call site | ❌ | Integration: insert, retrieve, clear round-trip |
| `CredentialCache` (DPAPI) | DPAPI failure throws to login `try/catch`; offline auth = string compare | ❌ | Integration: save+load round-trip, mismatch rejection, missing fields |
| `SyncService` (Timer + connectivity) | Token-less → 401 → data loss (F1); sync errors only `debugPrint` | ❌ | Unit: reentrancy guard, empty-queue skip, `ping` false skip, token-null handling |
| `AlochiImageCacheManager` | TLS bypass (F10); cache miss on fresh install before sync | ❌ | Unit: URL rewrite called; integration: cache hit vs miss |
| `PdfReport` / `PdfService` | Font load unguarded throws (F11) | ❌ | Unit: font load success; error path; score calculation; file path correctness |
| `assets/questions.json` | Malformed JSON → `FormatException` in `LocalQuestionsLoader` | ❌ | Unit: parse with valid/invalid/edge-case JSON |
| `connectivity_plus` | No connectivity → online check skipped correctly | ❌ | Unit: mock connectivity change triggers flush |

---

## Phase 6 — E2E Candidate Scenarios

### E2E-1: Student completes online exam end-to-end ⭐ P0

```
Path:
  Launch app
  → LoginScreen: enter credentials
  → POST /auth/login/ (mocked: 200 + token + session)
  → PackageScreen: packages listed (mocked: grade-filtered)
  → tap package
  → ConfirmScreen: details shown, tap "Start"
  → GET /packages/{id}/questions/ (mocked: 10 Math + 10 English)
  → TestScreen: answer all questions (A-D keyboard/tap)
  → finish / timer auto-submit
  → POST /results/ (mocked: 200 + math_score + eng_score + total_pct + wrong_answers)
  → ResultScreen: ring chart shows correct %, subject breakdown, wrong answers listed
  → PDF generated without error
  → "Keyingi talaba" returns to LoginScreen

Coverage status: MISSING
Priority: P0
Key assertions: answer map keyed by question.id; scores from server response displayed; PDF
file created; navigation stack cleared on "next student"
```

### E2E-2: Student completes offline (guest) exam end-to-end ⭐ P0

```
Path:
  Launch app
  → LoginScreen: tap "Oddiy kirish"
  → LocalGradeScreen step 1: select grade
  → step 2: select variant
  → step 3: enter name + PIN 1234
  → LocalTestScreen: answer all questions (shuffled options from assets/questions.json)
  → timer auto-submit
  → _finish() client-scores answers against q.correct
  → LocalResultScreen: pct displayed, per-subject breakdown, history written to SQLite
  → OfflineQueue.enqueueLocal() called
  → "Keyingi o'quvchi" returns to LocalGradeScreen

Coverage status: MISSING
Priority: P0
Key assertions: shuffled correct answer maps to original correct option; pct = correct*100/total;
per-subject counts correct; HistoryDb row inserted; queue row inserted with idempotency token
```

### E2E-3: Offline result syncs on reconnect ⭐ P0

```
Path:
  Complete offline exam while network unavailable
  → result enqueued to local_queue with idempotency token T1
  → Connectivity changes to online
  → SyncService._flushAll() triggered
  → api.ping() returns true
  → flushOfflineQueue() → flushLocal()
  → POST /result/ with Idempotency-Key: T1 (mocked: 200)
  → row deleted from local_queue
  → No duplicate row created

Coverage status: MISSING
Priority: P0
Key assertions: idempotency token T1 matches the enqueued token; row deleted on success;
second flush of same token does NOT create duplicate (409 → success true)
```

### E2E-4: Online exam fails network → enqueue → sync ⭐ P1

```
Path:
  Complete online exam
  → POST /results/ (mocked: network failure)
  → TestResult enqueued to queue (0/0/0 scores)
  → Network recovers → SyncService flushes queue
  → POST /results/ retried (mocked: 200 + scores)
  → ResultScreen: scores displayed correctly

Coverage status: MISSING
Priority: P1
Key assertions: queue row created with correct answers payload; retry uses same payload;
server-returned scores shown; queue row deleted
```

### E2E-5: App starts, sync flushes without login (F1 regression) ⭐ P0

```
Path:
  Queue contains pending authenticated result from previous session
  → App starts
  → SyncService.start() called (token = null in MonitoringApi)
  → SyncService attempts flush → POST /results/ with Authorization: Bearer null
  → Expected: guard should prevent flush until token is restored after login
  → Actual (current bug): no guard exists → 401 → attempts++ eventually purges result

Coverage status: MISSING (this test would confirm the known bug F1)
Priority: P0
Key assertions: when _token is null, flush should be deferred OR queue row preserved after
401; result NOT deleted from queue before user logs in
```

### E2E-6: Duplicate prevention on unstable network (F6 regression) ⭐ P1

```
Path:
  Offline exam completed → enqueued with token T1
  → DB row has token column = null (migration edge case)
  → flushLocal regenerates new token T2
  → POST /result/ with Idempotency-Key: T2 (mocked: 200)
  → Second flush (T2 again from DB) → 200 again → duplicate on server
  
  Expected: token should NEVER be regenerated on flush; original enqueue token always used

Coverage status: MISSING
Priority: P1
```

### E2E-7: "Next student" shared kiosk — credentials not leaked ⭐ P2

```
Path:
  Student A logs in, completes exam, taps "Keyingi talaba"
  → Navigation clears to LoginScreen
  → Login form should NOT show Student A's username/password
  → CredentialCache.loadCredentials() prefills from SAVED credentials
  → Student B enters their own credentials

Coverage status: MISSING
Priority: P2
Key assertions: Student A's session token cleared from MonitoringApi after result;
login form behaviour defined for shared-kiosk scenario
```

---

## Phase 7 — Release Blockers

### BLOCKER — Must fix before next release

| ID | Finding | Why a Blocker |
|---|---|---|
| F1 | API token never restored at startup; SyncService flushes token-less → 401 → results purged | Completed exams silently deleted from queue on next app launch. Data loss with no user notification. |
| R1 | Offline answer-shuffle correctness entirely untested | If the Fisher-Yates remap logic (`local_data.dart:57`) has any edge-case bug, all offline exam scores are wrong. Undetectable without automated tests. |
| R2 | Offline scoring logic entirely untested | `pct = totalOk * 100 ~/ _total` and subject counting at `local_test_screen.dart:159-175` could produce wrong scores silently. |
| R3 | Online answer ID keying entirely untested | `test_screen.dart:186-191` — wrong answer sent to server produces a plausible-looking but incorrect score. |
| **No CI test gate** | Zero tests run before release | Any regression can ship. A 2-minute CI step would catch all the above test failures automatically. |

### HIGH — Fix before production scale-up

| ID | Finding | Risk |
|---|---|---|
| F6 | Idempotency token regenerated when null during flush | Duplicate results on server; inflated statistics |
| R4 | Offline-enqueued online results carry 0/0/0 scores | Incorrect score on server after network recovery |
| F2 | `_get` malformed 2xx JSON throws `FormatException` uncaught | App crash at package/question load stage with no user-friendly message |
| F3 | `submitResultFull` swallows all errors silently | No way to distinguish server rejection from network failure; result lost |
| R5 | Section timer assumes contiguous math-first ordering from server | Timer/section display breaks if server changes question ordering |

### MEDIUM — Fix in next sprint

| ID | Finding | Risk |
|---|---|---|
| F5 | Malformed queue row never cleared by attempt cap | Permanently stuck queue row until 7-day age cutoff |
| F7 | No `CredentialCache.clear()` caller | Previous student's password persists in secure storage on shared kiosk machine |
| F8 | Stale cached token reused for online requests after offline login | 401 errors on first authenticated request after offline session |
| R6 | No idempotency key on authenticated `/results/` queue flush | Potential result duplication on network failure mid-POST |
| R7 | Subject string `'math'`/`'english'` vs `'m'`/`'e'` inconsistency | Wrong-answer display silently shows 0 counts if subject strings drift |

### LOW — Tech debt

| ID | Finding | Risk |
|---|---|---|
| F4 | `_fetchResultDetail` swallows all errors → `[]` | Wrong answers silently empty after server/network issue; user sees blank list |
| F9 | Background sync failures only `debugPrint` | No telemetry, no user feedback when results fail to sync repeatedly |
| F10 | TLS bypass for all image fetches on desktop (Win/macOS) | MITM can serve arbitrary image content; no code-signing of question images |
| F11 | PDF font asset load unguarded | PDF generation crashes if font asset missing from build; no graceful fallback |
| `main.dart:51-56` | TLS verification globally disabled on desktop | All HTTPS connections accept any certificate; `api.alochi.org` itself is vulnerable to MITM |
| `analysis_options.yaml` | `rules:` block empty | Static analysis at minimum baseline; no strict type, nullability, or print rules |
| `widget_test.dart` | Near-tautological smoke test | False sense of coverage; asserts nothing meaningful about startup UI |
