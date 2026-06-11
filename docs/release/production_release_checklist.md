# Interhouse Grade 2 — Production Release Checklist

**Release date:** 2026-06-12  
**Status:** APPROVED — ready for deployment  
**Executor:** _______________  
**Verified by:** _______________

---

## Pre-Deployment (backend team, before anything ships)

- [ ] Pull latest `main` on server: `cd ~/alochi && git pull origin main`
- [ ] Confirm uncommitted backend changes are present in the pull:
  - `apps/monitoring/models.py` — `detail` field on both models
  - `apps/monitoring/serializers.py` — `detail` in `TestResultCreateSerializer`
  - `apps/monitoring/views.py` — `detail` persisted in both views
  - `apps/monitoring/migrations/0009_monitoringresult_detail_testresult_detail.py`
  - `apps/monitoring/management/commands/activate_interhouse_g2.py`
- [ ] Take a database backup before touching anything:
  ```bash
  ssh alochi-devops@62.238.40.7
  pg_dump -h localhost -U alochi -d alochi -F c \
    -t monitoring_test_results -t mon_results -t monitoring_packages \
    -f /home/alochi-devops/backups/pre_interhouse_g2_$(date +%Y%m%d_%H%M%S).dump
  # Verify backup exists and is non-zero:
  ls -lh /home/alochi-devops/backups/pre_interhouse_g2_*.dump | tail -1
  ```

---

## Backend Deployment

### Step 1 — Rebuild Docker image
```bash
cd ~/alochi/infrastructure
docker compose build --no-cache backend
docker compose up -d backend
# Wait 10s, verify backend is healthy:
docker compose ps backend
curl -s http://localhost:8000/api/v1/monitoring/health/ | python3 -m json.tool
```

### Step 2 — Apply migration
```bash
docker exec alochi-backend python manage.py migrate monitoring
```

**Expected output:**
```
Operations to perform:
  Target specific migration: 0009_monitoringresult_detail_testresult_detail, from monitoring
Running migrations:
  Applying monitoring.0009_monitoringresult_detail_testresult_detail... OK
```

**Verify:**
```bash
docker exec alochi-backend python manage.py showmigrations monitoring | grep 0009
# Expected:  [X] 0009_monitoringresult_detail_testresult_detail
```

- [ ] Migration applied: `[X] 0009` shown
- [ ] No errors in output

### Step 3 — Activate Interhouse package
```bash
docker exec alochi-backend python manage.py activate_interhouse_g2
```

**Expected output (first run on empty prod):**
```
Archived N previously published package(s).
Created new Interhouse Grade 2 package.
Published package: [interhouse_g2] Interhouse Grade 2 English Test (id=<UUID>)

Done. Published packages: 1 (should be 1).
Package ID: <UUID>
```

**Or if package already exists:**
```
Archived 0 previously published package(s).
Found existing package: [interhouse_g2] Interhouse Grade 2 English Test (status=published)
Package already published (id=<UUID>)

Done. Published packages: 1 (should be 1).
```

- [ ] Exactly 1 published package after command
- [ ] Note the Package ID: _______________
- [ ] Verify via API: `curl https://api.alochi.org/api/v1/monitoring/packages/?grade=2`

### Step 4 — Verify migration data integrity
```bash
docker exec alochi-backend python manage.py shell -c "
from apps.monitoring.models import TestResult, MonitoringResult
from django.db import connection
with connection.cursor() as c:
    c.execute('SELECT COUNT(*) FROM monitoring_test_results')
    print('TestResult rows:', c.fetchone()[0])
    c.execute('SELECT COUNT(*) FROM mon_results')
    print('MonitoringResult rows:', c.fetchone()[0])
    c.execute(\"SELECT column_name FROM information_schema.columns WHERE table_name='monitoring_test_results' AND column_name='detail'\")
    print('detail column on TestResult:', 'EXISTS' if c.fetchone() else 'MISSING')
    c.execute(\"SELECT column_name FROM information_schema.columns WHERE table_name='mon_results' AND column_name='detail'\")
    print('detail column on MonitoringResult:', 'EXISTS' if c.fetchone() else 'MISSING')
"
```

**Expected:**
```
TestResult rows: <N>         ← must match pre-migration count
MonitoringResult rows: <N>   ← must match pre-migration count
detail column on TestResult: EXISTS
detail column on MonitoringResult: EXISTS
```

- [ ] TestResult row count unchanged: _______ rows
- [ ] MonitoringResult row count unchanged: _______ rows
- [ ] Both `detail` columns: EXISTS

---

## Flutter App Deployment

### Step 5 — Build Windows installer (on Windows or self-hosted runner)

**Option A — GitHub Actions (recommended):**
```bash
# Tag the release to trigger the build workflow
git tag v1.0.37 && git push origin v1.0.37
# Monitor: https://github.com/rusthype/alochi-monitoring/actions
```

**Option B — Local Windows build:**
```cmd
cd alochi-monitoring-flutter
flutter pub get
flutter build windows --release
# Installer location:
# build\windows\x64\runner\Release\AlochiMonitoring.exe
```

**Expected `flutter build windows` output:**
```
Building Windows application...
✓  Built build\windows\x64\runner\Release\AlochiMonitoring.exe
```

- [ ] Build succeeds with 0 errors
- [ ] Installer file exists and is > 20MB (includes assets)

### Step 6 — Distribute installer
- [ ] Upload new installer to `/var/www/downloads/` on server (replaces old version)
- [ ] Old installer archived (do not delete — keep for rollback)
- [ ] Exam machines updated: old process closed, new installer run

---

## Post-Deployment Verification

### Backend
```bash
# Package visible
curl -s "https://api.alochi.org/api/v1/monitoring/packages/?grade=2" | python3 -m json.tool

# detail column accepts JSON
docker exec alochi-backend python manage.py shell -c "
from apps.monitoring.models import MonitoringResult
import uuid
m = MonitoringResult.objects.create(
    name='post-deploy-check', grade=2, variant=1, source='check',
    pct=100, time='00:10', school_code='CHECK',
    vocab={'cor':0,'tot':0}, english={'cor':30,'tot':30}, math={'cor':0,'tot':0},
    client_token=str(uuid.uuid4()),
    detail={'test_key':'interhouse_g2','level':'Outstanding','total':30}
)
print('Inserted:', m.id, '| detail level:', m.detail.get('level'))
m.delete()
print('Cleaned up.')
"
```

- [ ] Package API returns 1 package with `status: published`
- [ ] Post-deploy DB write with `detail` succeeds and cleans up

### Online flow (manual, on exam machine)
- [ ] Login with a test student credential
- [ ] Package screen shows only "Interhouse Grade 2 English Test"
- [ ] Tapping it loads the test (not ConfirmScreen)
- [ ] All 5 sections render: Vocabulary (images), Grammar, Spelling, Reading, Writing
- [ ] Test completes and result screen shows shields/Cambridge/CEFR
- [ ] Result visible in Django admin with `detail` populated

### Offline flow (manual, on exam machine)
- [ ] Disconnect network
- [ ] Enter Offline mode → name + PIN 1234
- [ ] Select variant → test runs
- [ ] Result screen appears with shields display
- [ ] Reconnect → result syncs to backend
- [ ] `MonitoringResult` row in admin with `detail.level` populated

---

## Sign-off

| Item | Status | Initials |
|---|:---:|---|
| Database backup taken | | |
| Migration applied cleanly | | |
| Activation command ran | | |
| Row counts unchanged | | |
| Flutter build succeeded | | |
| Online flow tested | | |
| Offline flow + sync tested | | |
| Admin shows detail JSON | | |

**Release approved by:** _______________ **Date:** _______________
