# Alochi Monitoring App — Test Audit Report

**App:** `alochi-monitoring-flutter` (repo: `rusthype/alochi-monitoring`)  
**Version audited:** v1.0.36+36  
**Platform:** Flutter Windows desktop (also web/macOS capable)  
**Audit date:** 2026-06-11  
**Auditor:** QA Architecture Audit (read-only — no code was modified)

---

> ⚠️ **Scope correction:** The audit brief described features such as "attendance dashboard",
> "teacher-status monitoring", "poll monitoring", "realtime WebSocket events", and "Redis
> integration". **None of these exist in this app.** The Alochi Monitoring App is a
> **student test-taking app** for standardized school "monitoring" assessments (sinf test).
> Students log in, select a test package, answer multiple-choice questions, and receive a
> scored result. The QA strategy documented in this report targets the *actual* application
> architecture and its real risk areas.

---

## Table of Contents

1. [System Overview](#1-system-overview)
2. [Dependency Map](#2-dependency-map)
3. [Existing Test Coverage Audit](#3-existing-test-coverage-audit)
4. [Testing Tooling Inventory](#4-testing-tooling-inventory)
5. [CI/CD Test Integration](#5-cicd-test-integration)
6. [High-Risk Logic Catalogue](#6-high-risk-logic-catalogue)
7. [Testing Roadmap (4 Weeks)](#7-testing-roadmap-4-weeks)

---

## 1. System Overview

### Purpose

Alochi Monitoring is a Windows kiosk-style Flutter application used in Uzbekistani schools for
administering and scoring standardized multiple-choice assessments ("monitoring tests"). A
student (or unregistered guest) sits down at the computer, enters credentials, selects a test
package matching their grade, answers A/B/C/D questions in Math and English sections, and
receives a scored result with a downloadable PDF certificate.

The app operates **offline-first**: if the server is unreachable, answers and results are queued
locally and synced automatically when connectivity returns.

### Main Modules

| Module | Location | Role |
|---|---|---|
| Auth | `lib/features/auth/` | Login, offline session, credential caching |
| Test (online) | `lib/features/test/` | Package selection, question confirmation, exam runner |
| Result (online) | `lib/features/result/` | Server-scored result display, wrong-answer review, PDF export |
| Local test | `lib/features/local_test/` | Offline exam (no login required), client-side scoring, history |
| Core / API | `lib/core/api/` | HTTP client (`MonitoringApi`), all backend endpoints |
| Core / DB | `lib/core/db/` | Offline queue (SQLite), credential cache (secure storage), history DB |
| Core / Sync | `lib/core/sync/` | Background sync service (queue flush on connectivity change) |
| Core / Models | `lib/core/models/` | Shared data models: `StudentSession`, `TestPackage`, `Question`, `TestResult`, `WrongAnswer` |
| Core / Cache | `lib/core/cache/` | Disk image cache (flutter_cache_manager, 30-day TTL) |
| Core / Services | `lib/core/services/` | PDF generation (`pdf_service.dart`), tip copy (`pdf_tips.dart`) |
| Shared / Theme | `lib/shared/theme/` | Material3 light theme, Google Fonts Inter |
| Shared / Widgets | `lib/shared/widgets/` | `AppNetworkImage` (CachedNetworkImage wrapper) |

### Feature List

- **Online exam flow:** login with server credentials → select test package by grade → confirm
  student info and question count → answer Math + English questions (timer auto-advances at 0)
  → submit to server → display scored result (ring chart, subject breakdown, wrong answers) →
  download/print PDF → "next student" returns to login.
- **Offline (guest) exam flow:** tap "Oddiy kirish" → 3-step wizard (grade → variant → name +
  hardcoded PIN 1234) → answer questions loaded from bundled `assets/questions.json` → client
  scores answers → display local result → print PDF → result saved to local history → result
  queued for server submission.
- **Offline history:** view past guest-exam results from the local SQLite history DB.
- **Image pre-sync:** `SyncImagesButton` bulk-downloads all question/option images to disk cache
  for fully offline operation.
- **Auto-sync:** `SyncService` singleton flushes both result queues to the server on connectivity
  change, every 60 seconds, and on explicit `flushNow()` calls from result screens.
- **Update service:** referenced widget (`update_banner.dart` in the in-repo `monitoring-app/`
  variant); not found as a live feature in `alochi-monitoring-flutter/` at audit time.

### Navigation Structure

```
main() ──runZonedGuarded──► AlochiMonitoringApp
                              ├─ SyncService.instance.start()  [background, at launch]
                              └─ home: LoginScreen

LoginScreen
 ├─ (online/offline login) ──pushReplacement──► PackageScreen(session, offline?)
 │                                               └─ tap package ──push──► ConfirmScreen(session, pkg)
 │                                                                         └─ "Start" loads questions
 │                                                                            ──pushReplacement──► TestScreen(session, pkg, questions)
 │                                                                               └─ _finish() submit
 │                                                                                  ──pushReplacement──► ResultScreen(...)
 │                                                                                     ├─ PDF → OpenFilex
 │                                                                                     └─ "Keyingi talaba"
 │                                                                                        ──pushAndRemoveUntil──► LoginScreen
 ├─ "Oddiy kirish" ──push──► LocalGradeScreen (step: grade→variant→name+PIN)
 │                            └─ _startTest ──pushReplacement──► LocalTestScreen(questions)
 │                                              └─ _finish() (client score)
 │                                                 ──pushReplacement──► LocalResultScreen(...)
 │                                                    ├─ Print/Save PDF
 │                                                    ├─ "Keyingi o'quvchi" ──pushAndRemoveUntil──► LocalGradeScreen
 │                                                    └─ "Bosh sahifa" ──popUntil isFirst──► LoginScreen
 └─ "Oflayn Tarix" ──push──► HistoryScreen (HistoryDb read)
```

### Screens

| Screen | File | Type |
|---|---|---|
| LoginScreen | `lib/features/auth/login_screen.dart` | Entry / Auth |
| PackageScreen | `lib/features/test/package_screen.dart` | Online flow |
| ConfirmScreen | `lib/features/test/confirm_screen.dart` | Online flow |
| TestScreen | `lib/features/test/test_screen.dart` | Online flow — HIGH RISK |
| ResultScreen | `lib/features/result/result_screen.dart` | Online flow |
| PdfReport | `lib/features/result/pdf_report.dart` | Report generation |
| LocalGradeScreen | `lib/features/local_test/local_grade_screen.dart` | Offline flow |
| LocalTestScreen | `lib/features/local_test/local_test_screen.dart` | Offline flow — HIGH RISK |
| LocalResultScreen | `lib/features/local_test/local_result_screen.dart` | Offline flow |
| HistoryScreen | `lib/features/local_test/history_screen.dart` | Offline flow |
| SyncImagesButton | `lib/features/local_test/sync_images_button.dart` | Utility |

### State Management

**There is no state management library.** No Provider, Riverpod, Bloc, GetX, or
InheritedWidget-based store exists in `pubspec.yaml` or any import. All screen state is
local `StatefulWidget` + `setState`. Data flows between screens via **constructor injection**
at `Navigator.push` time — each screen receives only what it needs from its caller.

Three app-wide **global singletons** provide shared state:
- `api` — top-level `final MonitoringApi api = MonitoringApi()` in `api_client.dart:239`.
  Holds a mutable `String? _token`. This is the only cross-screen shared mutable state for
  the online flow.
- `SyncService.instance` — background sync singleton.
- `OfflineQueue` / `HistoryDb` — static-method SQLite gateways (lazy open, global database
  instance).

Implication for testing: screens are straightforward to widget-test in isolation because there
are no complex dependency injection containers to set up. The main challenge is mocking the
`api` global and the SQLite databases.

### API Architecture

Backend: Django REST API at `https://api.alochi.org/api/v1/monitoring`

All HTTP calls go through `MonitoringApi` (`lib/core/api/api_client.dart`):
- 20-second timeout, no built-in retries at HTTP layer.
- Auth via `Authorization: Bearer <token>` header for all authenticated endpoints.
- Guest endpoint (`POST /result/`) uses `Idempotency-Key` header instead of Bearer.
- Errors: transport failures → `ApiException(0, <message>)`. 4xx/5xx → `ApiException(status, detail)`.
- Background sync: `SyncService` triggers flush; the `MonitoringApi.flushOfflineQueue()` method
  drains both queue tables and calls `purgeStale`.

### "Realtime Architecture"

**There is no realtime architecture.** No WebSocket connection, no Redis pub/sub, no Server-Sent
Events, no long-polling. The closest analogue is:
- `SyncService`: periodic 60-second `Timer` + connectivity-change hook that attempts a
  `POST /results/` or `POST /result/` submission.
- `ResultScreen.initState` and `dispose` both call `SyncService.instance.flushNow()` to
  eagerly attempt queue drain when a result is shown.

### Local Storage

| Store | Technology | Location | Contents |
|---|---|---|---|
| Offline queue | SQLite (sqflite_common_ffi) | `{support_dir}/monitoring_queue.db` | `queue` (authenticated results), `local_queue` (guest results + idempotency token), `tg_queue` (legacy, dead) |
| History | SQLite (sqflite_common_ffi) | `{support_dir}/monitoring_history.db` | Guest exam results for offline history view |
| Credentials | flutter_secure_storage (DPAPI) | Windows Credential Manager | username, password (plaintext), token, student metadata |
| Image cache | flutter_cache_manager (disk) | `{cache_dir}/alochi_images/` | Cached question/option images, 30-day TTL, max 500 items |
| Test result PDF | File system | `{documents_dir}/Natija_<name>_<date>.pdf` | Generated per-student result PDF |
| Local questions | App asset bundle | `assets/questions.json` | All offline test questions, options, correct answers for grades 1–4 |

### Background Services

| Service | File | Trigger | Action |
|---|---|---|---|
| SyncService | `lib/core/sync/sync_service.dart` | connectivity_plus change; 60s Timer; explicit `flushNow()` | Pings API; if online, flushes `OfflineQueue` + `LocalQueue` → server |

---

## 2. Dependency Map

### Backend APIs

| Method | Endpoint | Auth | Used by |
|---|---|---|---|
| `POST` | `/auth/login/` | None | LoginScreen |
| `GET` | `/ping/` | Optional | LoginScreen (online check), SyncService |
| `GET` | `/pack/version/` | Optional | (guest PIN fetch) |
| `GET` | `/packages/?grade=N` | Bearer | PackageScreen |
| `GET` | `/packages/{id}/questions/?variant=N` | Bearer | ConfirmScreen |
| `POST` | `/results/` | Bearer | TestScreen (online submission); OfflineQueue flush |
| `GET` | `/my-results/{id}/` | Bearer | ResultScreen (fetch wrong answers after submit) |
| `POST` | `/result/` | `Idempotency-Key` (no Bearer) | LocalResultScreen; LocalQueue flush |

### Redis — NOT USED

No Redis client, no pub/sub, no `redis` package in `pubspec.yaml` or `pubspec.lock`.

### WebSocket — NOT USED

No `web_socket_channel`, no `dart:io` WebSocket usage, no streaming protocol. All communication
is standard HTTP request/response.

### Telegram — LEGACY DEAD CODE

`offline_queue.dart` contains a `tg_queue` table and Telegram Bot API endpoint
(`https://api.telegram.org/bot{token}/sendMessage`, lines 204-208). This code is **never
called** by any live path in the app — no bot token is configured, no `enqueueTelegram` call
site exists in the active codebase. It is an artifact of an earlier architecture.

### External Services

| Service | Purpose | Risk if unavailable |
|---|---|---|
| `api.alochi.org` | Auth, test packages, scoring, wrong-answer fetch | Offline fallback path activates; results queued locally |
| Telegram Bot API | LEGACY — unused | None |
| Google Fonts CDN | Inter font loading at runtime | Falls back to system font (Flutter cache hit normally) |

### Database Dependencies

| DB | Schema version | Tables | Failure mode |
|---|---|---|---|
| `monitoring_queue.db` | v4 | `queue`, `local_queue`, `tg_queue` | First open throws if FFI init fails; no app-level catch |
| `monitoring_history.db` | v1 | `history` | Same; `clearHistory`/`getHistory` calls not caught at call-site |

---

## 3. Existing Test Coverage Audit

**Total:** 4 test files, 7 test cases across the entire suite.

### File-by-File Analysis

#### `test/api_client_test.dart`

| Attribute | Detail |
|---|---|
| **Type** | Unit (pure function, no Flutter binding) |
| **What it claims to test** | `MonitoringApi.fixImageUrl` |
| **What is actually tested** | URL normalization: null/blank → empty; relative path with space + query → absolute + percent-encoded; duplicate slashes collapsed; already-absolute URL trimmed; protocol-relative `//cdn...` → `https://` |
| **Cases** | 3 groups covering ~6 individual assertions |
| **Quality** | **8/10** |
| **Justification** | Tests real, non-trivial logic (slash-collapsing, query preservation, percent-encoding). Assertions are specific string comparisons on exact output. No mocking needed. Exercises an actually-shipped helper that is called everywhere images load. |
| **Gaps** | URL with fragment (`#`); plain `http://`; URL with no path after host (line 54 `pathStart == -1` branch); non-ASCII characters. Entire rest of `MonitoringApi` (HTTP calls, `ApiException`, `login`, `submitResultFull`, etc.) is completely untested. |

#### `test/login_online_check_test.dart`

| Attribute | Detail |
|---|---|
| **Type** | Unit (async, injectable ping callback) |
| **What it claims to test** | `checkOnlineWithRetry` |
| **What is actually tested** | (1) Ping succeeds on 3rd attempt → returns `true`, attempts counter == 3. (2) Ping always fails → returns `false`, attempts == 3. |
| **Cases** | 2 |
| **Quality** | **7/10** |
| **Justification** | Clean design: the function under test accepts an injectable ping callback, letting tests use a hand-rolled closure without a mocking library. `retryDelay: Duration.zero` avoids real waits. Assertions on both return value AND attempt count are meaningful. |
| **Gaps** | `onTimeout: () => false` path (line 22 of `login_screen.dart`); the `catch (_)` swallow path (line 24); custom `attempts` and `retryDelay` values; behaviour when the first two pings timeout but the third succeeds. |

#### `test/app_network_image_test.dart`

| Attribute | Detail |
|---|---|
| **Type** | Widget |
| **What it claims to test** | `AppNetworkImage` widget |
| **What is actually tested** | Empty URL (`' '`) + explicit `height`/`width` → the rendered `SizedBox` reserves the specified dimensions |
| **Cases** | 1 |
| **Quality** | **5/10** |
| **Justification** | Tests a real behaviour (dimension reservation on empty URL prevents layout collapse). Assertion is correct. |
| **Gaps** | Non-empty URL path (the widget's main use case); error placeholder; loading placeholder; full-screen zoom dialog; `find.byType(SizedBox)` is fragile (multiple `SizedBox`es in the tree would cause `tester.widget<SizedBox>` to throw on ambiguous match). |

#### `test/widget_test.dart`

| Attribute | Detail |
|---|---|
| **Type** | Smoke |
| **What it claims to test** | `AlochiMonitoringApp` root widget |
| **What is actually tested** | `pumpWidget(AlochiMonitoringApp())` completes without throwing; `find.byType(AlochiMonitoringApp)` finds 1 widget |
| **Cases** | 1 |
| **Quality** | **2/10** |
| **Justification** | Near-tautological: the assertion merely confirms the widget exists after it was pumped. Any real startup crash would be the only thing this catches, and Flutter's error boundaries make even that uncertain. |
| **Gaps** | Does not assert on any rendered child (login form, logo, text). Does not call `pumpAndSettle`. Does not verify online-check or credential-prefill initial state. |

### Summary Table

| File | Type | Cases | Quality | Covers |
|---|---|---|---|---|
| `test/api_client_test.dart` | Unit | 3 | 8/10 | `fixImageUrl` URL normalization |
| `test/login_online_check_test.dart` | Unit | 2 | 7/10 | `checkOnlineWithRetry` retry loop |
| `test/app_network_image_test.dart` | Widget | 1 | 5/10 | `AppNetworkImage` empty-URL layout |
| `test/widget_test.dart` | Smoke | 1 | 2/10 | App constructs (trivial) |
| **TOTAL** | | **7** | | **~2 files of logic, 0 flows** |

---

## 4. Testing Tooling Inventory

### Present

| Tool | Source | Notes |
|---|---|---|
| `flutter_test` (SDK) | `pubspec.yaml:40` | Standard widget/unit/integration test runner |
| `flutter_lints: ^4.0.0` | `pubspec.yaml:42` | Baseline lint rules |
| `analysis_options.yaml` | root | Includes `package:flutter_lints/flutter.yaml`; the `rules:` block is **empty** — no custom or strict rules active |

### Absent (confirmed via `pubspec.lock` inspection)

| Tool | Status | Impact |
|---|---|---|
| `mockito` | ❌ Not installed | Cannot generate typed mocks without a mocking library |
| `mocktail` | ❌ Not installed | Same — codegen-free alternative also absent |
| `build_runner` | ❌ Not installed | No code generation pipeline for mocks |
| `integration_test` (Flutter SDK package) | ❌ No `integration_test/` directory | No E2E test capability |
| Golden test tooling (`golden_toolkit`, `alchemist`) | ❌ Not installed | No visual regression tests |
| `patrol` / `flutter_driver` | ❌ Not installed | No automated UI driving |
| Coverage configuration | ❌ No `coverage/`, no `lcov.info` | Coverage never measured |

### `analysis_options.yaml` Assessment

- Extends `package:flutter_lints/flutter.yaml` — sensible baseline.
- `rules:` section is present but **empty/commented out** (`# rules:`).
- Recommended additions for a test-taking app: `strict-casts: true`, `strict-raw-types: true`,
  `avoid_print: true`, `prefer_const_constructors`, `prefer_final_fields`.

---

## 5. CI/CD Test Integration

Two GitHub Actions workflows exist in `.github/workflows/`:

### `build-windows.yml` — Primary pipeline

| Trigger | Push to `main`; tags `v*`; `workflow_dispatch` |
|---|---|
| Steps | checkout → setup Flutter 3.x stable → `flutter pub get` → `flutter build windows --release` → Authenticode sign → ZIP + MSIX + Inno Setup → SHA256 → GitHub Release → winget PR |
| `flutter test` | ❌ **ABSENT** |
| `flutter analyze` | ❌ **ABSENT** |
| Effect | Tests are never executed as part of the release gate. A failing test cannot block a merge or a release. |

### `windows_build.yml` — Legacy/manual workflow

| Trigger | `workflow_dispatch` only |
|---|---|
| Steps | checkout → Flutter → `flutter pub get` → `flutter build windows` → zip → Inno Setup → upload artifact → hardcoded release `v1.0.31` |
| `flutter test` | ❌ **ABSENT** |
| `flutter analyze` | ❌ **ABSENT** |
| Note | Hardcoded version `v1.0.31` is stale vs `pubspec.yaml` `1.0.36+36` — this workflow is outdated |

**Net result:** Zero test automation. Tests run only if a developer manually invokes
`flutter test` locally. There is no quality gate before any commit, PR, or release.

---

## 6. High-Risk Logic Catalogue

These are the specific code paths where a bug would silently produce incorrect exam scores,
lost results, or security issues. All are currently **completely untested.**

| # | Risk | File:Line | Description |
|---|---|---|---|
| R1 | **Offline answer shuffle correctness** | `local_data.dart:41-64` | Fisher-Yates shuffle of answer options (`idx`) followed by `correct = 'abcd'[idx.indexOf(origIdx)]`. If the index mapping logic is wrong, every offline test produces incorrect answers. Option images must stay index-aligned (`optionImages: idx.map(...)`). Single most fragile correctness point in the app. |
| R2 | **Offline score math** | `local_test_screen.dart:159-175` | `pct = totalOk * 100 ~/ _total` (integer division). Counting loop keyed on `_answers[i] == q.correct` (string comparison). Per-subject (`mathOk`/`engOk`) and per-topic aggregation. Subject discrimination uses `q.subject == 'm'` (local JSON convention). |
| R3 | **Online answer ID keying** | `test_screen.dart:186-191` | `answersMap[questions[i].id] = _answers[i]` — answers keyed by server question ID (not index). Any off-by-one between `_answers` (index-keyed Map) and `questions` list ordering would silently send wrong answers to the server. |
| R4 | **0/0/0 scores enqueued offline** | `test_screen.dart:195, 219` | Online `TestResult` sent to server with `mathScore=0, engScore=0, totalPct=0` — server computes scores. If the submission fails and falls to `OfflineQueue.enqueue`, the queued payload has **zero scores**. When later flushed, correctness depends on the server re-scoring on re-submit. |
| R5 | **Section/timer assumes math-first** | `test_screen.dart:41-51, 119-137` | Math questions counted as `questions.where((q) => q.isMath)`. Timer resets to 40-minute English timer via `_navigate`/`switchToEng` only when current index moves past `_mathCount`. Mixed question ordering from the server would corrupt both the section progress display and the per-section timers. |
| R6 | **No idempotency on authenticated queue flush** | `offline_queue.dart:84-113` | The `flush()` path (authenticated `/results/`) has **no `Idempotency-Key` header**, unlike the guest `flushLocal()` path. A network failure where the server processed the request but the client didn't receive the response causes the row to remain in `queue` and be retried — potentially duplicating the server-side result. |
| R7 | **Subject string inconsistency** | `models.dart:82`, `result_screen.dart:768`, `pdf_report.dart:472` | Model `Question.isMath` checks `subject == 'math'`; server wrong-answer display filters on `'english'`; local question JSON uses `'m'`/`'e'`. A server-side change to subject naming conventions would silently miscategorize Math vs. English breakdowns in the result screen and PDF. |
| F1 | **Token not restored at startup** | `main.dart:26` vs `api_client.dart:67` | `SyncService.instance.start()` is called in `main()` before any login occurs. `MonitoringApi._token` is `null` at this point. Background queue flush attempts `POST /results/` with no Bearer token → server returns 401 → `attempts` incremented → after 10 failures the row is permanently deleted from the queue. Previously submitted online exam results can be **silently lost**. |
| F6 | **Idempotency token regenerated on flush** | `offline_queue.dart:139` | `flushLocal` regenerates a fresh UUID when the stored token is null. The original token was saved at enqueue time; if a DB read loses it, deduplication is defeated and the server may record the result twice. |
| F8 | **Plaintext password in secure storage** | `credential_cache.dart:24, 31, 51` | The raw password is stored to enable offline auth (plaintext string compare). The cached (possibly stale/expired) token is reused for online requests after an offline login session. No expiry check on the cached token. |
| F10 | **TLS verification disabled for images** | `image_cache_manager.dart:34` | `badCertificateCallback: (_,__,___) => true` accepts any TLS certificate for all image fetches on Windows/macOS (comment: "Windows SSL muammosi"). A compromised network can serve arbitrary images including crafted content. |

---

## 7. Testing Roadmap (4 Weeks)

> See `monitoring_app_testing_roadmap.md` for the full per-week detail.

### Week 1 — Highest ROI unit tests + CI gate

- Add `mocktail` to dev dependencies.
- Add `flutter test` + `flutter analyze` steps to `build-windows.yml`.
- Write unit tests for R1 (answer shuffle), R2 (offline scoring), R3 (online answer keying),
  URL normalization edge cases (F-fragment, `http://`, no-path branch), retry edge cases
  (timeout path, exception path).

### Week 2 — Integration tests (mocked boundaries)

- `MonitoringApi` HTTP paths via mock HTTP client.
- `OfflineQueue` and `HistoryDb` SQLite (in-memory FFI).
- `SyncService` trigger and flush logic.
- `CredentialCache` round-trip (including offline-session mismatch).

### Week 3 — End-to-end integration tests

- `integration_test/` package for the full online exam flow.
- Full offline (local) exam flow including `pushAndRemoveUntil` navigation teardown.
- Reconnect-and-sync scenario.

### Week 4 — Regression suite + coverage gate

- Golden tests for `ResultScreen` ring chart and `LocalResultScreen` breakdown.
- PDF generation smoke test (golden byte-count or font-load assertion).
- Add `--coverage` to CI and set a minimum threshold.
- Tighten `analysis_options.yaml` lint rules.
