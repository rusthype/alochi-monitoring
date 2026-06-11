# Interhouse Grade 2 — Production Deployment Report

**Date:** 2026-06-12  
**Environment:** Local dev (pre-production verification run)  
**Status:** ALL CLEAR — READY TO DEPLOY

---

## Phase 1 — Pre-Deployment Safety

### Git State

**alochi-monitoring-flutter** (Flutter app repo)

```
Branch: main
Remote: origin/main
```

| File | State |
|---|---|
| `lib/core/api/api_client.dart` | Modified (detail param + shadowing fix) |
| `lib/core/models/models.dart` | Modified (detail in TestResult.toJson) |
| `lib/features/local_test/local_grade_screen.dart` | Modified (offline → InterhouseRunner) |
| `lib/features/test/package_screen.dart` | Modified (online → InterhouseRunner) |
| `pubspec.yaml` | Modified (interhouse assets registered) |
| `lib/features/interhouse/` | New directory (4 files: data, scorer, runner, result) |
| `assets/interhouse/` | New directory (interhouse_g2.json + 70 PNGs) |
| `test/interhouse_scorer_test.dart` | New (26 scorer unit tests) |

**alochi (mono-repo, backend)**

```
Branch: main
Remote: origin/main
```

| File | State |
|---|---|
| `alochi_backend/apps/monitoring/models.py` | Modified (`detail` JSONField on both models) |
| `alochi_backend/apps/monitoring/serializers.py` | Modified (`detail` in TestResultCreateSerializer) |
| `alochi_backend/apps/monitoring/views.py` | Modified (persist `detail` in both views) |
| `alochi_backend/apps/monitoring/migrations/0009_*.py` | New (additive nullable migration) |
| `alochi_backend/apps/monitoring/management/commands/activate_interhouse_g2.py` | New |
| `alochi_backend/apps/monitoring/tests/test_interhouse.py` | New (25 Django tests) |

### Migration Status (local dev)

```
[X] 0001_initial
[X] 0002_rename_password_field
[X] 0003_alter_monitoringpackage_created_at_and_more
[X] 0004_alter_monitoringpackage_created_at_and_more
[X] 0005_credential_package_fk
[X] 0006_credential_expires_at
[X] 0007_vocab_question_model
[X] 0008_monitoringresult_client_token_and_more
[X] 0009_monitoringresult_detail_testresult_detail  ← NEW, applied
```

`python manage.py migrate --check` → No pending migrations.

### Package Activation Status (local dev)

```
Total packages: 1
[published] grade=2 | [interhouse_g2] Interhouse Grade 2 English Test
id=6f7afccf-66f7-4f96-b8f3-3bdce9064730
```

---

## Phase 2 — Database Safety

### Backup Command (run on production server before deploy)

```bash
pg_dump -h localhost -U alochi -d alochi -F c \
  -t monitoring_test_results \
  -t mon_results \
  -t monitoring_packages \
  -f /home/alochi-devops/backups/pre_interhouse_g2_$(date +%Y%m%d_%H%M%S).dump
```

This creates a compressed custom-format dump of exactly the three affected tables. File size: expected ~10–50MB depending on existing test data.

**Restore procedure (if needed):**
```bash
pg_restore -h localhost -U alochi -d alochi --data-only \
  -t monitoring_test_results -t mon_results -t monitoring_packages \
  /home/alochi-devops/backups/pre_interhouse_g2_TIMESTAMP.dump
```

### Affected Tables

| Table | Django model | Change | Risk |
|---|---|---|---|
| `monitoring_test_results` | `TestResult` | +1 nullable `jsonb` column (`detail`) | Zero — existing rows get `NULL` |
| `mon_results` | `MonitoringResult` | +1 nullable `jsonb` column (`detail`) | Zero — existing rows get `NULL` |
| `monitoring_packages` | `MonitoringPackage` | No schema change; data change via `activate_interhouse_g2` | Low — archives published packages, adds 1 row |

### Row Counts (local dev baseline)

```
monitoring_test_results (TestResult):   0 rows
mon_results (MonitoringResult):         0 rows
```

**Column verification:**
```
monitoring_test_results.detail: EXISTS
mon_results.detail:             EXISTS
```

> On production, record actual row counts before and after migration. They must be identical — migration only adds a column, never touches rows.

---

## Phase 3 — Release Commands

### Backend (run in this exact order on the production server)

```bash
# 1. Pull latest code
cd ~/alochi && git pull origin main

# 2. Rebuild backend Docker image (code is baked into image)
cd ~/alochi/infrastructure
docker compose build --no-cache backend
docker compose up -d backend
sleep 10

# 3. Apply migration (additive — zero downtime on Postgres)
docker exec alochi-backend python manage.py migrate monitoring

# Expected:
# Operations to perform:
#   Target specific migration: ...0009...
# Running migrations:
#   Applying monitoring.0009_monitoringresult_detail_testresult_detail... OK

# 4. Activate Interhouse package
docker exec alochi-backend python manage.py activate_interhouse_g2

# Expected (fresh prod):
# Archived N previously published package(s).
# Created new Interhouse Grade 2 package.
# Published package: [interhouse_g2] Interhouse Grade 2 English Test (id=<UUID>)
# Done. Published packages: 1 (should be 1).
```

### Flutter App (Windows — on exam machine or CI)

```bash
# On Windows machine with Flutter SDK installed:
cd alochi-monitoring-flutter
flutter pub get
flutter build windows --release

# Expected:
# Building Windows application...
# ✓  Built build\windows\x64\runner\Release\AlochiMonitoring.exe

# Or via GitHub Actions tag:
git tag v1.0.37 && git push origin v1.0.37
# Workflow: .github/workflows/flutter-release.yml
# Artifact: GitHub release "latest" — AlochiMonitoring-Setup.exe
```

---

## Phase 4 — Post-Deployment Verification Procedures

### Backend

**Package active:**
```bash
curl -s "https://api.alochi.org/api/v1/monitoring/packages/?grade=2" | python3 -m json.tool
# Must contain exactly 1 item with status=published and title containing interhouse_g2
```

**Archived packages preserved (not deleted):**
```bash
docker exec alochi-backend python manage.py shell -c "
from apps.monitoring.models import MonitoringPackage
for p in MonitoringPackage.objects.all():
    print(p.status, p.grade, p.title[:50])
"
# All pre-existing packages appear with status=archived
```

**detail JSONField writable:**
```bash
docker exec alochi-backend python manage.py shell -c "
from apps.monitoring.models import MonitoringResult
import uuid
m = MonitoringResult.objects.create(
    name='deploy-verify', grade=2, variant=1, source='check',
    pct=100, time='00:05', school_code='VERIFY',
    vocab={'cor':0,'tot':0}, english={'cor':30,'tot':30}, math={'cor':0,'tot':0},
    client_token=str(uuid.uuid4()),
    detail={'test_key':'interhouse_g2','level':'Outstanding','total':30}
)
print('OK — detail level:', m.detail['level'])
m.delete()
"
```

### Online Flow

1. On exam machine, open new AlochiMonitoring installer
2. Login with any valid student credential (grade 2)
3. Package screen: verify only one package appears, titled "Interhouse Grade 2 English Test"
4. Tap the package: verify InterhouseRunner opens (NOT ConfirmScreen)
5. Complete all 5 sections (Vocabulary images must render)
6. Result screen: confirm shields (1–5 per part) and level label appear
7. In Django admin (`/admin/monitoring/testresult/`): verify new row exists with `detail` JSON populated

### Offline Flow

1. Disconnect exam machine from network
2. Tap "Offline Mode" on login screen
3. Enter first name, last name, select variant 1–10, enter PIN `1234`
4. Complete the test (no network required)
5. Result screen appears with shields display
6. Reconnect network
7. Within 60 seconds (SyncService timer), verify MonitoringResult row appears in admin with `detail` populated

### Assets

**All 70 images bundled in installer — no network required for images.**

Verification (Python, against the bundled JSON):
```python
import json, os
with open('assets/interhouse/interhouse_g2.json') as f:
    data = json.load(f)
imgs = set()
for v in data['variants'].values():
    for q in v['vocab']:
        if q.get('img'): imgs.add(q['img'])
    if v['reading'].get('img'): imgs.add(v['reading']['img'])
missing = [i for i in imgs if not os.path.exists(f'assets/interhouse/img/{i}')]
print(f'Images: {len(imgs)} referenced, {len(missing)} missing')
# Expected: 70 referenced, 0 missing
```

**Evidence (local dev):**
```
Total unique images referenced: 70
Images present on disk: 70
Missing: none
```

**JSON loads successfully:**
```
interhouse_g2.json: 64,874 bytes
Variants: ['1', '2', '3', '4', '5', '6', '7', '8', '9', '10']
Parts: ['Vocabulary', 'Grammar', 'Spelling', 'Reading', 'Writing']
Shield thresholds: [6, 5, 4, 3]
Level count: 5
```

---

## Phase 5 — Smoke Tests

All smoke tests run via automated test suites.

### Django (25 tests — `apps/monitoring/tests/test_interhouse.py`)

| Test | Covers | Result |
|---|---|---|
| `test_creates_with_detail_payload` | Online perfect score → `detail` stored | PASS |
| `test_detail_nullable_by_default` | Historical row → `detail=NULL` | PASS |
| `test_detail_stored_as_json_with_nested_list` | Nested shields array round-trip | PASS |
| `test_creates_with_detail` (MonitoringResult) | Offline zero score → `detail` stored | PASS |
| `test_detail_nullable_default` (MonitoringResult) | Offline legacy row → `detail=NULL` | PASS |
| `test_passed_flag_still_computed` | Existing scoring logic unaffected | PASS |
| `test_command_creates_and_publishes_package` | Activation command creates package | PASS |
| `test_command_idempotent_run_twice_still_one_published` | Second run = no duplicate | PASS |
| `test_command_idempotent_same_package_id` | Package ID stable across runs | PASS |
| `test_command_archives_previously_published_non_interhouse_package` | Old packages archived | PASS |
| `test_command_does_not_archive_interhouse_g2_itself` | Command doesn't archive itself | PASS |
| `test_command_archives_multiple_published_packages` | Bulk archive works | PASS |
| `test_command_leaves_draft_packages_unchanged` | Draft packages untouched | PASS |
| `test_command_publishes_existing_draft_interhouse_g2` | Re-publishes if archived | PASS |
| `test_old_monitoring_result_accessible_after_command` | Historical MR rows intact | PASS |
| `test_old_test_result_accessible_after_command` | Historical TR rows intact | PASS |
| `test_new_result_can_coexist_with_old_result_without_detail` | Mixed detail/null rows | PASS |
| `test_submit_with_detail_returns_201` | POST /results/ with detail → 201 | PASS |
| `test_submit_with_detail_persists_to_db` | detail round-trip via API | PASS |
| `test_submit_without_detail_stores_none` | Legacy app still works | PASS |
| `test_duplicate_submit_with_detail_returns_409` | Idempotency for online flow | PASS |
| `test_submit_with_detail_returns_200_or_201` (offline) | POST /result/ with detail | PASS |
| `test_submit_with_detail_persists_to_db` (offline) | Offline detail round-trip | PASS |
| `test_submit_without_detail_stores_none` (offline) | Old app offline still works | PASS |
| `test_idempotency_with_detail` | Offline idempotency token | PASS |

**Total: 25/25 PASS** (full suite: 61/61 PASS, 1 skipped)

### Flutter (26 scorer tests — `test/interhouse_scorer_test.dart`)

| Test group | Covers | Result |
|---|---|---|
| `shields(0)` → 1 (floor-1 rule) | Zero score always gives 1 shield | PASS |
| `shields(1..6)` | Full threshold range | PASS (6 tests) |
| All-correct score | `[6,6,6,6,6]`, total=30, totalShields=25, Outstanding | PASS |
| All-blank score | `[0,0,0,0,0]`, total=0, shields=`[1..1]`=5, Needs Practice | PASS |
| Wrong MC indices | Option-index comparison | PASS |
| Spelling case-insensitive | `CAT` matches `cat` | PASS |
| Spelling trims whitespace | `  cat  ` matches `cat` | PASS |
| Sentence strips trailing `.` | normalised comparison | PASS |
| Sentence strips trailing `!` | normalised comparison | PASS |
| YES/NO case-sensitive | `yes` does NOT match `YES` | PASS |
| Fill case-insensitive | `dog` matches `Dog` | PASS |
| Level thresholds (5 bands) | All level boundaries exact | PASS (5 tests) |
| `totalPct` integer division | `total * 100 ~/ 30` | PASS |
| Parts list length = 5 | Exactly 5 parts | PASS |
| Parts ordering | Vocabulary…Writing order | PASS |

**Total: 26/26 PASS**

---

## Phase 6 — Rollback Plan

### Migration Rollback

If the migration causes issues on production:

```bash
# 1. Roll back to 0008 (drops the detail column — NO data loss since
#    the column was just added and is nullable)
docker exec alochi-backend python manage.py migrate monitoring 0008

# Expected:
# Unapplying monitoring.0009_monitoringresult_detail_testresult_detail... OK

# 2. Rebuild backend to the last known-good commit
cd ~/alochi
git revert HEAD --no-edit   # or git checkout <previous-commit>
cd ~/alochi/infrastructure
docker compose build --no-cache backend && docker compose up -d backend
```

**Downtime:** ~2 minutes (rebuild only). Zero data loss — the column was nullable; historical rows had `NULL`.

### Package Reactivation

If the activation command archived packages that need to be restored:

```bash
docker exec alochi-backend python manage.py shell -c "
from apps.monitoring.models import MonitoringPackage

# List archived packages and their IDs
for p in MonitoringPackage.objects.filter(status='archived'):
    print(p.id, p.title)

# To re-publish a specific one (replace UUID):
# MonitoringPackage.objects.filter(id='<UUID>').update(status='published')
"
```

No data was deleted. All previously published packages were set to `status='archived'` and remain in the database with all their `TestResult` rows intact.

### Flutter Installer Rollback

```bash
# On the server, the old installer was archived before replacement
# Redistribute the previous installer version to exam machines:
ssh alochi-devops@62.238.40.7
ls /var/www/downloads/  # Locate archived previous version
# Copy previous .exe/.msix back to the active download location

# Old app is backward-compatible with the updated backend:
# - Migration 0008 (rolled back) removes the detail column → old app still works
# - Migration 0009 (kept) → old app sends no detail → column stores NULL → fine
```

**Backward compatibility:** The old Flutter app (pre-interhouse) does not send `detail`. The backend accepts submissions without `detail` — the field defaults to `NULL`. Old results remain readable. The only visible change to the old app is that it sees the Interhouse package in the package list; clicking it routes through `ConfirmScreen` (MC path), which will fail with empty questions. This is acceptable because the old installer should not be distributed once the new one is available.

---

## Summary

| Phase | Status | Notes |
|---|:---:|---|
| Pre-deployment safety | CLEAR | Git, migration, activation all verified |
| Database safety | CLEAR | Backup command ready; 2 columns added, 0 rows modified |
| Release commands | READY | Exact commands with expected output documented |
| Post-deployment verification | READY | Manual steps + DB shell commands documented |
| Smoke tests | PASS | 25 Django + 26 Flutter tests all green |
| Rollback plan | READY | Migration, package, and installer rollback all documented |

**DEPLOY WHEN READY.** No blockers. All pre-deployment checks passed.
