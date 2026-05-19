# Alochi Monitoring — Flutter API Hujjat

## Backend
**URL:** `https://api.alochi.org/api/v1/`  
**Backend:** Django (alochi.org ning asosiy backenди)  
**Auth:** JWT Bearer token

---

## Endpoints

### 🔐 Authentication

#### Login
```
POST /monitoring/login/
Body: { "username": "...", "password": "...", "school_code": "..." }
Response: { "token": "jwt...", "student_id": "...", "name": "...", "grade": 2, "variant": 1 }
```

---

### 📦 Pack API (savollar)

#### Versiya tekshirish
```
GET /monitoring/pack/version/
Response: {
  "version": 2,
  "checksum": "f67a8d31...",
  "updated_at": "2026-05-19T..."
}
```

#### Savollar yuklab olish
```
GET /monitoring/pack/?grade=2
Response: {
  "version": 2,
  "checksum": "f67a8d31...",
  "vocab": [
    { "id": "uuid", "cat": "Animals", "ans": "cat",
      "wrong": ["dog","bird","fish"], "img": "https://api.alochi.org/media/..." }
  ],
  "english": [
    { "id": "uuid", "grade": 2, "sect": "Grammar - Unit 1",
      "q": "It is ___", "opts": ["red","blue","green"], "ans": "red" }
  ]
}
```

---

### 📊 Natija yuborish

#### HTML test natijasi (bot ga yuboradi)
```
POST /monitoring/html/submit/
Body: {
  "name": "Ali Valiyev",
  "grade": 2,
  "variant": "B",
  "pct": 78,
  "vocab":   { "cor": 45, "tot": 58 },
  "english": { "cor": 18, "tot": 25 },
  "math":    { "cor": 19, "tot": 25 },
  "time":    "01:23:45"
}
Response: { "ok": true, "sent": 3 }
```

---

### 👑 Boss CRUD (JWT kerak)

#### Vocab savollar
```
GET    /monitoring/boss/vocab/          → ro'yxat
POST   /monitoring/boss/vocab/          → qo'shish (multipart/form-data: cat, ans, wrong, image)
PATCH  /monitoring/boss/vocab/<uuid>/   → tahrirlash
DELETE /monitoring/boss/vocab/<uuid>/   → o'chirish
```

#### Ingliz savollar
```
GET    /monitoring/boss/english/?grade=2  → ro'yxat (grade filter)
POST   /monitoring/boss/english/          → qo'shish
PATCH  /monitoring/boss/english/<uuid>/   → tahrirlash
DELETE /monitoring/boss/english/<uuid>/   → o'chirish
```

---

## Flutter App Arxitekturasi

```
lib/
├── core/
│   ├── api/
│   │   └── api_client.dart        # HTTP client, JWT, login, pack API
│   ├── db/
│   │   └── credential_cache.dart  # SharedPreferences: token, offline session
│   ├── models/
│   │   └── models.dart            # StudentSession, TestPackage, ...
│   ├── services/
│   │   ├── pack_cache.dart        # Versiya cache: API → localStorage → fallback
│   │   ├── connectivity_service.dart  # Internet holati monitoring
│   │   └── update_service.dart    # GitHub Releases API, auto-update check
│   └── data/
│       └── local_test_data.dart   # Bundled fallback (offline)
├── features/
│   ├── auth/
│   │   └── login_screen.dart      # Login + Oddiy kirish (PIN bilan)
│   ├── test/
│   │   ├── package_screen.dart    # Bosh ekran
│   │   ├── local_test_screen.dart # Vocab + English test
│   │   └── confirm_screen.dart    # Testni boshlash tasdiqi
│   ├── result/
│   │   └── celebration_screen.dart # Test natija + BARAKALLA
│   └── home/
│       └── update_banner.dart     # Yangi versiya banneri
└── shared/
    └── theme/
        └── app_theme.dart         # Ranglar, shriftlar
```

## Fayllar joylashuvi (Windows)

```
Program Files\Alochi Monitoring\   ← Dastur fayllar (o'qish uchun)
  alochi_monitoring.exe
  flutter_windows.dll
  data\flutter_assets\

%APPDATA%\alochi_monitoring\       ← Foydalanuvchi ma'lumotlari
  shared_preferences.json          ← Token, cache, sozlamalar
  (uninstall paytida SAQLANADI)
```

## Xavfsizlik

- ✅ Barcha API muloqoti HTTPS
- ✅ Bot token serverda (.env), clientda emas
- ✅ JWT token AppData da (encrypted SharedPreferences)
- ✅ Program Files da maxfiy ma'lumot yo'q
- ✅ Guest login PIN bilan himoyalangan
- ⚠️ PIN hozircha hardcode (TODO: API dan olish)
