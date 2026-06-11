# Alochi Monitoring App — Test Coverage Matrix

**App:** `alochi-monitoring-flutter` v1.0.36+36  
**Audit date:** 2026-06-11  
**Legend:** ✅ Covered · ⚠️ Partially covered · ❌ Not covered

---

## Coverage Matrix by Feature / Subsystem

| Feature / Subsystem | Unit | Widget | Integration | E2E | Overall |
|---|:---:|:---:|:---:|:---:|:---:|
| **AUTH** | | | | | |
| Login form renders, prefills saved credentials | ❌ | ❌ | ❌ | ❌ | ❌ |
| Online login success path (`POST /auth/login/`) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Online login 400 (wrong creds) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Online login 429 (rate limit) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Offline login (credential cache match) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Offline login rejected (cred mismatch) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Connectivity check (`checkOnlineWithRetry`) | ✅ | — | — | — | ⚠️ |
| … retry-on-timeout path | ❌ | — | — | — | ❌ |
| … exception-swallow path | ❌ | — | — | — | ❌ |
| **PACKAGE SCREEN** | | | | | |
| Package list loads for correct grade | ❌ | ❌ | ❌ | ❌ | ❌ |
| Empty package list (no tests for grade) | ❌ | ❌ | ❌ | ❌ | ❌ |
| API error displays correctly | ❌ | ❌ | ❌ | ❌ | ❌ |
| Logout clears token and returns to Login | ❌ | ❌ | ❌ | ❌ | ❌ |
| **CONFIRM SCREEN** | | | | | |
| Student / package details render | ❌ | ❌ | ❌ | ❌ | ❌ |
| Question fetch (`GET /packages/{id}/questions/`) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Empty/malformed question list handled | ❌ | ❌ | ❌ | ❌ | ❌ |
| **ONLINE TEST RUNNER (TestScreen)** | | | | | |
| Math section timer (30 min) | ❌ | ❌ | ❌ | ❌ | ❌ |
| English section timer (40 min reset) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Timer-expired auto-submit | ❌ | ❌ | ❌ | ❌ | ❌ |
| A/B/C/D answer selection + 720ms auto-advance | ❌ | ❌ | ❌ | ❌ | ❌ |
| Answer map keyed by `question.id` (R3) | ❌ | — | — | — | ❌ |
| Section split assumes math-first ordering (R5) | ❌ | — | — | — | ❌ |
| **ONLINE SCORING & SUBMISSION** | | | | | |
| `POST /results/` with correct payload | ❌ | — | ❌ | ❌ | ❌ |
| Server returns scores → displayed correctly | ❌ | — | ❌ | ❌ | ❌ |
| Submission fails → enqueue with 0/0/0 (R4) | ❌ | — | ❌ | ❌ | ❌ |
| HTTP 409 treated as `synced:true` | ❌ | — | ❌ | — | ❌ |
| `_get` 2xx malformed JSON → handled (F2) | ❌ | — | ❌ | — | ❌ |
| **RESULT SCREEN** | | | | | |
| Score ring chart renders correct percentage | ❌ | ❌ | ❌ | ❌ | ❌ |
| Passing threshold (≥60%) logic | ❌ | ❌ | — | — | ❌ |
| Wrong-answer breakdown (by subject) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Subject filter `'math'`/`'english'` string (R7) | ❌ | — | — | — | ❌ |
| Wrong answers fetch failure → empty list (F4) | ❌ | ❌ | ❌ | — | ❌ |
| `SyncService.flushNow()` called in initState + dispose | ❌ | — | ❌ | — | ❌ |
| PDF generation trigger | ❌ | ❌ | ❌ | ❌ | ❌ |
| "Next student" navigation to Login | ❌ | ❌ | ❌ | ❌ | ❌ |
| **PDF GENERATION** | | | | | |
| `PdfReport` — score percentages calculated | ❌ | — | — | — | ❌ |
| Font asset loaded (Inter-Regular + Inter-Bold) | ❌ | — | — | — | ❌ |
| Font load failure handling (F11 — unguarded) | ❌ | — | — | — | ❌ |
| Wrong-answer images fetched + embedded | ❌ | — | ❌ | — | ❌ |
| File written to documents directory | ❌ | — | ❌ | — | ❌ |
| PdfService (local PDF) — tips thresholds | ❌ | — | — | — | ❌ |
| **LOCAL GRADE WIZARD (LocalGradeScreen)** | | | | | |
| 3-step navigation (grade → variant → name) | ❌ | ❌ | ❌ | ❌ | ❌ |
| Hardcoded PIN `1234` gate | ❌ | ❌ | — | — | ❌ |
| Wrong PIN rejected | ❌ | ❌ | — | — | ❌ |
| `LocalQuestionsLoader` loads correct grade/variant | ❌ | — | ❌ | — | ❌ |
| **LOCAL TEST RUNNER (LocalTestScreen)** | | | | | |
| Single timer `_total * 72` seconds | ❌ | ❌ | ❌ | ❌ | ❌ |
| Answer selection + auto-advance | ❌ | ❌ | ❌ | ❌ | ❌ |
| **LOCAL SCORING / ANSWER REMAPPING** | | | | | |
| `_shuffleOptions` Fisher-Yates shuffle correct (R1) | ❌ | — | — | — | ❌ |
| `correct` letter remapped after shuffle (R1) | ❌ | — | — | — | ❌ |
| Option images stay aligned post-shuffle (R1) | ❌ | — | — | — | ❌ |
| Subject discrimination `'m'`/`'e'` (R2) | ❌ | — | — | — | ❌ |
| Per-question `_answers[i] == q.correct` comparison (R2) | ❌ | — | — | — | ❌ |
| `pct = totalOk * 100 ~/ _total` integer division (R2) | ❌ | — | — | — | ❌ |
| Per-topic aggregation correctness | ❌ | — | — | — | ❌ |
| **LOCAL RESULT & HISTORY** | | | | | |
| `LocalResultScreen` score display | ❌ | ❌ | ❌ | ❌ | ❌ |
| `HistoryDb.insertResult` persists result | ❌ | — | ❌ | — | ❌ |
| History insert failure is non-fatal (silent) | ❌ | — | ❌ | — | ❌ |
| `OfflineQueue.enqueueLocal` payload correctness | ❌ | — | ❌ | — | ❌ |
| `HistoryScreen` renders records | ❌ | ❌ | ❌ | ❌ | ❌ |
| `clearHistory` deletes all records | ❌ | — | ❌ | — | ❌ |
| Passing threshold `pct >= 60.0` in history display | ❌ | — | — | — | ❌ |
| **OFFLINE QUEUE** | | | | | |
| `enqueue` / `enqueueLocal` write to SQLite | ❌ | — | ❌ | — | ❌ |
| `flush` — success path deletes row | ❌ | — | ❌ | — | ❌ |
| `flush` — failure path increments `attempts` | ❌ | — | ❌ | — | ❌ |
| `flush` — malformed row never increments (F5) | ❌ | — | ❌ | — | ❌ |
| `flushLocal` — idempotency token reuse | ❌ | — | ❌ | — | ❌ |
| `flushLocal` — token regenerated when null (F6) | ❌ | — | ❌ | — | ❌ |
| `purgeStale` — drops rows at 10 attempts | ❌ | — | ❌ | — | ❌ |
| `purgeStale` — drops rows > 7 days old | ❌ | — | ❌ | — | ❌ |
| Schema migrations v1→v4 | ❌ | — | ❌ | — | ❌ |
| **SYNC SERVICE** | | | | | |
| Connectivity-change → flush triggered | ❌ | — | ❌ | — | ❌ |
| 60s timer → flush triggered | ❌ | — | ❌ | — | ❌ |
| Reentrancy guard (`_flushing`) | ❌ | — | ❌ | — | ❌ |
| Empty-queue short-circuit (no ping/flush) | ❌ | — | ❌ | — | ❌ |
| `api.ping()` false → skip flush | ❌ | — | ❌ | — | ❌ |
| Token-less startup flush → 401 → data loss (F1) | ❌ | — | ❌ | — | ❌ |
| `flushNow()` called from result screens | ❌ | — | ❌ | — | ❌ |
| **CREDENTIAL CACHE** | | | | | |
| `saveCredentials` + `saveSession` round-trip | ❌ | — | ❌ | — | ❌ |
| `loadOfflineSession` — exact credential match | ❌ | — | ❌ | — | ❌ |
| `loadOfflineSession` — mismatch rejected | ❌ | — | ❌ | — | ❌ |
| Stale token reused for online requests (F8) | ❌ | — | ❌ | — | ❌ |
| No `clear()` caller — password persists (F7) | ❌ | — | — | — | ❌ |
| **IMAGE CACHE / APP NETWORK IMAGE** | | | | | |
| Empty URL → `SizedBox` layout reservation | ✅ | ✅ | — | — | ⚠️ |
| Non-empty URL renders via `CachedNetworkImage` | ❌ | ❌ | ❌ | ❌ | ❌ |
| Error placeholder on fetch failure | ❌ | ❌ | — | — | ❌ |
| Full-screen zoom dialog | ❌ | ❌ | — | — | ❌ |
| TLS bypass for Windows image fetches (F10) | ❌ | — | — | — | ❌ |
| **API CLIENT** | | | | | |
| `fixImageUrl` — relative, absolute, protocol-relative | ✅ | — | — | — | ⚠️ |
| `fixImageUrl` — fragment, `http://`, no-path edge cases | ❌ | — | — | — | ❌ |
| `ApiException` — status message mapping | ❌ | — | — | — | ❌ |
| 20s timeout → `ApiException(0,...)` | ❌ | — | ❌ | — | ❌ |
| `_get` malformed 2xx JSON → `FormatException` (F2) | ❌ | — | ❌ | — | ❌ |
| `submitResultFull` error swallow (F3) | ❌ | — | ❌ | — | ❌ |
| `_fetchResultDetail` failure → `[]` (F4) | ❌ | — | ❌ | — | ❌ |
| Bearer header attached correctly | ❌ | — | ❌ | — | ❌ |
| Guest `Idempotency-Key` header sent | ❌ | — | ❌ | — | ❌ |

---

## Covered / Partially / Not Covered Summary

### ✅ Covered

- `fixImageUrl` (relative/absolute/protocol-relative URLs) — `test/api_client_test.dart`
- `checkOnlineWithRetry` success and exhaustion paths — `test/login_online_check_test.dart`
- `AppNetworkImage` empty-URL layout reservation — `test/app_network_image_test.dart`
- `AlochiMonitoringApp` constructs without throwing — `test/widget_test.dart`

### ⚠️ Partially Covered

- `fixImageUrl` — 3 of ~5 edge-case branches tested; fragment/`http://`/no-path missing.
- `checkOnlineWithRetry` — 2 of 4 paths tested; timeout and exception paths missing.
- `AppNetworkImage` — only the empty-URL fallback tested; main rendering path untested.
- `AlochiMonitoringApp` smoke — only construction; no rendered UI assertions.

### ❌ Not Covered

**Everything else.** The complete online exam flow, offline exam flow, all scoring logic (both
server-trust and client-scoring), offline queue, sync service, credential cache, history DB,
PDF generation, and all 11 risk findings (F1–F11) are **completely untested.**

Estimated coverage: **< 5% of codebase** — concentrated in two small utility functions
(`fixImageUrl` ~40 lines, `checkOnlineWithRetry` ~15 lines) out of ~3,000+ lines of logic.

---

## Priority Order for Closing Gaps

Based on risk × impact:

| Priority | Area | Why |
|---|---|---|
| P0 — Immediate | R1: Offline answer-shuffle correctness | Silent wrong grades; impossible to detect without tests |
| P0 — Immediate | R2: Offline score integer math | Incorrect pass/fail decisions for students |
| P0 — Immediate | R3: Online answer ID keying | Wrong answers silently sent to server → wrong server score |
| P0 — Immediate | F1: Token not restored at startup → data loss | Completed online exams lost from queue |
| P1 — Near-term | F6: Idempotency token loss → duplicate submission | Duplicate server records |
| P1 — Near-term | F2: `_get` malformed JSON → unhandled exception | App crash on server response anomaly |
| P1 — Near-term | R4: 0/0/0 scores in offline-enqueued authed results | Correctness of flushed results |
| P1 — Near-term | R5: Section/timer math-first assumption | Wrong timer shown if server changes question order |
| P2 — Medium | F3, F5, F8, F10, R6, R7 | Silent failures, security, consistency |
| P2 — Medium | All UI widget tests | Login, package, confirm, result, history screens |
| P3 — Long-term | PDF, image cache, E2E flows | Completeness |
