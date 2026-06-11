# Offline Sync — Kod o'zgarishlari (sessiya hisoboti)

> A'lochi Monitoring offline natija yuborish tizimini ishonchli holatga keltirish.
> Maqsad: natija **yo'qolmasin**, **dublikat bo'lmasin**, **darhol + ishonchli** serverga (DB + Telegram) yetib borsin va panelда o'quvchи profilида ko'rinsin.

Sana: 2026-06-06

---

## CLIENT — `alochi-monitoring` (5 commit)

### `4b00cfb` — Outbox model + idempotency token
**Nega:** offline natija qayta yuborilganда serverда dublikat qator + dublikat Telegram paydo bo'lardi; natija app crash bo'lsa yo'qolishi mumkin edi.

| Fayl | O'zgarish |
|------|-----------|
| `pubspec.yaml` | `uuid: ^4.5.1` qo'shildi |
| `lib/core/api/api_client.dart` | `newIdempotencyToken()` (UUID) helper; `submitLocalResult(payload, token)` endi `Idempotency-Key` header bilan yuboradi |
| `lib/core/db/offline_queue.dart` | DB **v4**; `local_queue`ga `token` ustuni; `enqueueLocal`/`flushLocal` token bilan ishlaydi |
| `lib/core/sync/sync_service.dart` | `flushNow()` public metodi |
| `lib/features/local_test/local_result_screen.dart` | **Outbox:** natija avval queue'ga (token bilan) yoziladi → darhol flush. Eski "to'g'ridan yubor / xato bo'lsa queue" dual-path olib tashlandi |

### `9d6490c` — Natija ekranlaridan flushNow
**Nega:** natija faqat ekran ochilganda bir marta flush bo'lardi; chiqishда (Keyingi/Bosh sahifa/orqaga) qayta urinish yo'q edi; online ekранда umuman flush yo'q edi.

| Fayl | O'zgarish |
|------|-----------|
| `lib/features/local_test/local_result_screen.dart` | `dispose()`да `flushNow()` |
| `lib/features/result/result_screen.dart` | sync import; `initState()` oxiriда + `dispose()`да `flushNow()` |

### `ef36b0a` — `flushOfflineQueue` o'lik stubни tuzatish
**Nega:** `flushOfflineQueue()` doim `0` qaytaradigan, hech qayerda ishlatilmaydigan o'lik kod edi.

| Fayl | O'zgarish |
|------|-----------|
| `lib/core/api/api_client.dart` | `flushOfflineQueue()` endi haqiqiy — `OfflineQueue.flush(submitResult)` + `flushLocal(submitLocalResult)` ikkalаsини drenajlaydi |
| `lib/core/sync/sync_service.dart` | `_flushAll()` endi `api.flushOfflineQueue()`ga delegat qiladi; ortiqcha import/pendingCount kodи olib tashlandi |

### `d5a6150` — `purgeStale` navbat tozalash
**Nega:** `attempts` faqat oshib borardi, hech ishlatilmasdi → doim xato beradigan (buzuq) natija abadiy navbatда qolib qayta urinaverardi.

| Fayl | O'zgarish |
|------|-----------|
| `lib/core/db/offline_queue.dart` | `purgeStale()` — `attempts >= 10` YOKI 7 kundan eski qatorlarни o'chiradi (queue/local_queue ikkala shart, legacy tg_queue faqat yosh) |
| `lib/core/api/api_client.dart` | `flushOfflineQueue()` ichида flushdan keyin `purgeStale()` chaqiriladi |

### `7f917ce` — Performance: flush oldidan gate (ping + bo'sh-navbat)
**Nega:** interfeys "ulangan" desa-yu internet yo'q bo'lsa, navbatdagi **har bir** element POST'и **20s timeout**ни kutardi (N element = N×20s behuda, har 60s'da). Bo'sh navbatда ham har 60s'да behuda flush ishlardi.

| Fayl | O'zgarish |
|------|-----------|
| `lib/core/sync/sync_service.dart` | `_flushAll()` endi flushdan oldin: (1) navbat bo'sh bo'lsa (`pendingCount + pendingLocalCount == 0`) tarmoqqa tegmaydi; (2) bitta arzon `api.ping()` bilan haqiqiy internetни tekshiradi — yo'q bo'lsa o'tkazib yuboradi (N×20s o'rniga 1 ta tekshiruv). `offline_queue.dart` importi qayta qo'shildi |

---

## BACKEND — `alochi` (2 commit)

### `c1b4c32c` — Guest `/result/` idempotency dedupe
**Nega:** guest endpoint tokenни o'qimasди, har POST yangi qator yaratarди → klиент qayta yuborса dublikat.

| Fayl | O'zgarish |
|------|-----------|
| `apps/monitoring/models.py` | `MonitoringResult.client_token` (indexed; null bo'lmaganда unique constraint) |
| `apps/monitoring/migrations/0008_monitoringresult_client_token_and_more.py` | yangi field + constraint |
| `apps/monitoring/views.py` | `MonitoringResultSubmitView` endi `Idempotency-Key`ни o'qiydi — token mavjud bo'lsa yangi qator yaratмай `duplicate:true` qaytaradi; poyga uchun `IntegrityError` lookup |

### `ec441936` — O'quvchи "Nazorat natijalari"га offline natija
**Nega:** o'quvchи profilидаги panel faqat `TestResult` (FK bilan)ни o'qирди; offline `MonitoringResult` (ism bilan) ko'rinmasди ("Test natijalari yo'q").

| Fayl | O'zgarish |
|------|-----------|
| `apps/web_panel/api/core_views.py` (`academics()`) | `MonitoringResult`ни o'quvchи **ismi bo'yicha** (`name__iexact`) topib, mavjud `recent_tests` + `test_count` + `avg_score`га **birlashtiradi**. Frontend tegilmaди. Migration kerak emas |

---

## Umumiy oqim (natijada)

```
Test tugadi (local/offline)
  └─> local_result_screen: enqueueLocal(payload, token)      ← yo'qolmaydi (instant, durable)
       └─> SyncService.flushNow()  (+ ekrandan chiqishda dispose'da ham)
SyncService:  flushNow / connectivity / 60s timer
  └─> _flushAll
       ├─ navbat bo'sh?            → to'xta (tarmoqqa tegmaydi)
       ├─ api.ping() == false?     → to'xta (internet yo'q, navbatda qoladi)
       └─ api.flushOfflineQueue()
            ├─ OfflineQueue.flush(submitResult)             (online navbat)
            ├─ OfflineQueue.flushLocal(submitLocalResult)   (local, Idempotency-Key bilan)
            └─ OfflineQueue.purgeStale()                    (attempts>=10 yoki >7 kun → o'chiradi)
Server /result/:  token ko'rsa → dublikat yaratmaydi (bitta qator, bitta Telegram)
Panel:  academics() → MonitoringResult ism bo'yicha → o'quvchи "Nazorat natijalari"да ko'rinadi
```

## Asos (oldingi commit)
- `e647a21` — markaziy `SyncService` yaratilishi; lokal natijani hardcode-Telegram o'rniga server `/result/`ga yo'naltirish. Yuqoridagi client commitlar shu asos ustiga qurildi.

## Tekshiruv
- Client: har commitда `flutter analyze` → **No issues found**.
- Backend: `python manage.py check` → **0 xato**; `makemigrations --check` → toza.
- Hammasi `main`ga push qilingan (CI/CD auto-deploy).

## Deploy eslatmalari
- Backend imageга baked → push = rebuild + migration (avtomatik).
- Server `.env`да `MONITORING_BOT_TOKEN` / `MONITORING_ADMIN_IDS` bo'lishi shart (Telegram uchun).
- **Client:** yangi `.exe`/`.msix` build qilinib o'qituvchilarga tarqatilishi kerak — aks holda eski build hali natijani to'g'ridan Telegramга yuboradi (serverga emas).
