# LAN Hub (Faza 3) — o'qituvchi kompyuteri hub, o'quvchi kompyuterlari klient

Faza 1+2 (USB paket, anti-cheat) ustiga qurilgan. Internet kerak emas: bitta sinf LAN'ida.

```
o'qituvchi PC                                   o'quvchi PC'lar (<= 60)
  .alochipack ni PIN bilan ochadi                 "O'qituvchi kompyuteriga ulanish"
  hub (shelf, 0.0.0.0:8080..8090)  <--- HTTP ---  sinf kodi -> sessiya tokeni
  UDP e'lon (8081) ------------------------------> topilgan hublar ro'yxati
  yagona HMAC zanjir yozuvchi                     natija -> shifrlangan outbox -> hub ack
  BITTA .alochires eksport
```

## Ishlatish

1. O'qituvchi: Oflayn rejim -> **Lokal server yoqish (LAN)** -> paket + PIN -> monitoring ekrani ochiladi,
   serverni ishga tushiradi va **6 xonali sinf kodini** ko'rsatadi.
2. O'quvchi: Oflayn rejim -> **O'qituvchi kompyuteriga ulanish** -> topilgan kompyuterni tanlang
   (yoki `IP:port` kiriting) -> kodni kiriting -> mavjud guruh/o'quvchi tanlash oqimi.
3. Test oxirida o'quvchi "Javoblaringiz saqlandi" ekranini ko'radi (ball yo'q). Natija avval o'quvchi
   PC'dagi shifrlangan outbox'ga yoziladi, hub qabul qilgach (ack) o'chadi; hub o'chiq bo'lsa qayta uriniladi.
4. O'qituvchi: **Natijalarni eksport (.alochires)** — butun sinf uchun bitta fayl.

**Windows Firewall:** o'qituvchi PC'da birinchi ishga tushirishda "Allow access" so'raydi (TCP 8080).
O'quvchi PC'da UDP 8081 tinglash uchun ham so'raydi; ruxsat berilmasa avtomatik qidiruv ishlamaydi,
qo'lda `IP:port` ishlayveradi (faqat chiquvchi TCP kerak). Ko'p PC'li maktabda qoidani oldindan
(GPO / `netsh advfirewall`) qo'shing.

## Endpointlar (JSON; `/health` va `/join`dan boshqasi `Authorization: Bearer <token>`)

| | |
|---|---|
| `GET /health` | `{ok}` |
| `POST /join {code, machine_id, device_name?}` | `{token, hub_name, pack_uuid, school_id, school_code, ...}` |
| `POST /keepalive` | 5 soniyada bir; "aloqa yo'q" (15 s) shundan hisoblanadi |
| `POST /ping` | `sessionPing` shakli -> `locked`, `extra_time_seconds` (jami), `commands`, `terminated`, `conflict`, `proctor_token`, `proctor_interval_ms`, `target_width` |
| `POST /frame?session_id=..&frame_type=..` | tana = xom JPEG (multipart emas); javob `/ping` shaklida |
| `POST /result` + `Idempotency-Key` | tana `{payload, incidents, clock_flags}`; `payload` = onlayn `/result/` tanasi |
| `GET /groups`, `/students?group_id=`, `/catalog?group_id=`, `/test?key=`, `/packages`, `/package_questions`, `/diagnostics` | paket mazmuni (javob kaliti yo'q) |
| `GET /media/<sha256>.<ext>` | rasm; ism to'liq oq ro'yxat regex'i bilan tekshiriladi |

## Xavfsizlik modeli

- **Auth:** sinf kodi (CSPRNG, 6 raqam, `constant-time` taqqoslash) -> 32 bayt CSPRNG token, faqat xotirada.
  Kod IP bo'yicha 5 xatodan keyin 60 s bloklanadi (monotonic soat; tizim sanasini o'zgartirish yordam bermaydi).
  Qo'shimcha global chegara: istalgan manbalardan 60 xato/60 s -> hamma uchun 60 s (ko'p manzildan
  brute-force'ga qarshi; evaziga xato kodlar oqimi qonuniy ulanishni 1 daqiqaga kechiktirishi mumkin).
  Kodni "Yangilash" almashtiradi (mavjud tokenlar qoladi); hub qayta ishga tushsa yangi kod, eski tokenlar bekor.
- **Paket PIN'i va zanjir kaliti** hub jarayonidan tashqariga chiqmaydi; o'quvchi PC PIN'ni bilmaydi.
- **Natija:** hub tekshiradi (o'quvchi roster'da, `(student, group)` juftligi bor, `test_key` paketniki — serverning
  `student_invalid`/`test_not_in_pack` mantiqiga mos, lekin qat'iyroq: bazasi yo'qligi uchun paketda bo'lmagan
  har qanday bo'sh bo'lmagan kalit rad etiladi), keyin mavjud `PackResultsDb.append` orqali zanjirga qo'shadi.
  Idempotent: bir xil kalit — ack, ikkinchi qator yo'q. Hub **hech narsani ballamaydi**.
- **Chegaralar:** tana `join` 1 KB / `ping` 64 KB / `frame` 512 KB / `result` 1 MB; `Content-Length` majburiy
  (411), katta bo'lsa 413; JSON chuqurligi 24 / 200k tugun; tana o'qish muddati 10 s; tokenga so'rov tezligi
  (bucket 120, 40/s); IP bo'yicha autentifikatsiyasiz so'rovlar (bucket 30, 1/s); bir vaqtda 128 so'rov;
  60 klient, bitta IP'dan 8 tagacha; bitta PC'dan 100 natija; zanjir 4800 yozuv / ~8 MB gacha (server importi
  5000 / 10 MB dan oshsa butun faylni rad etadi). Incident/clock flag ro'yxatlari serverning 201/101, 1 KiB,
  48 KiB chegarasiga qisqartiriladi (ortig'i `*_overflow` hisoblagichiga).
- **Xato javoblari** faqat barqaror kod (`{"error": "..."}`); stack, yo'l, PIN, kalit, kod, token yo'q.
  Loglarda token/kod/PIN yo'q.
- **Ekran kadrlari** faqat hub xotirasida (har PC uchun oxirgi *keyframe*), diskka yozilmaydi; test tugasa,
  hub to'xtasa yoki paket yopilsa o'chadi. Patch kadrlar saqlanmaydi (hub rasm yig'maydi); ko'rilayotgan
  o'quvchidan har javobda `request_keyframe` so'raladi.
- **Bir o'quvchi — ikki PC:** ikkinchi PC `conflict: true` oladi (mavjud "boshqa qurilmada" xabari). Birinchi PC
  15 s jim bo'lsa — egallab olinadi va eskisiga `terminated` yuboriladi.

## QABUL QILINGAN CHEKLOVLAR (hujjatlangan)

- **HTTP, TLS yo'q.** Sinf kodi va tokenlar shu LAN segmentini tinglay oladigan har kimga ko'rinadi
  (jumladan kadrlar va natijalar). Mo'ljal: izolyatsiyalangan sinf tarmog'i. Umumiy Wi-Fi'da ishlatmang.
- Kodni bilgan har qanday ulangan PC rostersdagi **istalgan o'quvchi nomidan** natija yubora oladi (hub o'quvchini
  PC'ga bog'lamaydi; server qayta ballaydi, o'qituvchi esa jonli ro'yxatni ko'radi). Kod ma'lum bo'lib qolsa —
  "Kodni yangilash" va keraksiz PC'ni uzish.
- Sarlavha (header) bosqichidagi sekin ulanishlar (slowloris) va ochiq-bekor TCP ulanishlar sonini Dart
  `HttpServer` darajasida cheklab bo'lmaydi (`idleTimeout` 15 s). Firewall / tarmoq darajasida cheklang.
- UDP e'lon `255.255.255.255` va har interfeysning `/24` broadcast manziliga yuboriladi (dart:io netmask
  bermaydi); boshqa niqobli tarmoqda `255.255.255.255` yoki qo'lda `IP:port` ishlatiladi.
- Assets testlar (unit1, combined, interhouse ...) USB rejimidagi kabi hub'dan o'tmaydi (o'z runner'lari
  onlayn navbatga yozadi) — bu Faza 1 dan meros.
