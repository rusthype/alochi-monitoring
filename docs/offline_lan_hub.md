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
| `POST /leave` | klient xushmuomala chiqadi (uzish / tasdiqlashni rad etish) |
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
- **Chegaralar:**
  - Tana: `join` 1 KB / `ping` 64 KB / `frame` 512 KB / **`result` 64 KB** (eng yomon real natija — 300 savollik
    test, 100 ta uzun matnli javob: ~43 KB; diagnostika ~16 KB; `test/lan_hub_review_test.dart` o'lchaydi va
    shu shakllarni HTTP orqali qabul qilishni isbotlaydi; zaxira >= 40%). Bitta so'rov eksportga eng ko'pi ~130 KB qo'sha oladi. `Content-Length`
    majburiy (411), katta bo'lsa 413; JSON chuqurligi 24 / 200k tugun, `Infinity`/`NaN` 400; tana o'qish muddati
    kichik endpointlarda 3 s, natijada 6 s, kadrda 8 s.
  - **Zanjir hajmi eksport birligida o'lchanadi.** JSON `\` va `"` ni ikki marta ekranlaydi (bir marta
    `payload_json`da, yana eksport konvertida), shuning uchun saqlangan bayt hisobi 2 baravar kam baholardi.
    Hub endi `export_format.dart` dagi **eksportyorning o'zi ishlatadigan** funksiyalar bilan har yozuvning
    haqiqiy plaintext hajmini o'lchaydi va `<= 9 MiB` (server cheklovi 10 MiB = 10 485 760 B plaintext; 1 MiB
    zaxira) va `<= 4800` yozuv bilan cheklaydi; oshsa `507 pack_full`. Tekshirish → yozish → hisoblash bitta
    mutex ostida (parallel so'rovlar chegaradan oshira olmaydi).
  - **Natija kvotasi manba manzil (IP) bo'yicha** (hub ishlash davomida): 150 natija va 2.5 MiB eksport-bayt;
    token yoki `machine_id` bo'yicha EMAS — ikkalasini qayta join qilib yangilash mumkin. Oshsa `403 client_quota`.
  - **O'quvchi bo'yicha kvota va rezerv (N-2).** IP kvotasi yetarli emas (4 manzil/IP-alias pack'ni to'ldira oladi),
    shuning uchun: har roster o'quvchisiga ko'pi bilan **3 natija va 192 KB** eksport-bayt (`403 student_quota`;
    sana zanjirdan o'qiladi, hub qayta ishga tushsa ham saqlanadi) va natijasi hali yo'q har o'quvchi uchun
    **24 KB rezerv**: qo'shimcha natija faqat `ishlatilgan + rezerv + yozuv <= 9 MiB` bo'lsa qabul (`507 pack_full`).
    Rezerv byudjetning yarmidan oshmaydi (katta roster hubni butunlay to'sib qo'ymasin). Mijoz `student_quota`ni
    "rad etilgan" deb saqlaydi (yo'qolmaydi); `pack_full` esa navbatda qoladi. Qoldiq xavf: kodni bilgan PC o'quvchi
    NOMIDAN 3 ta keraksiz natija yuborib, o'sha o'quvchining haqiqiy natijasini to'sishi mumkin — bu "kodni
    bilgan istalgan PC istalgan o'quvchi nomidan yubora oladi" cheklovining davomi (pastga qarang).
  - O'qituvchining o'z natijasi (`OfflinePackSession.recordResult`) hub bilan **bitta mutex** (`chainLock`) ostida
    yoziladi va bir xil hisoblagichga (`ChainUsage`) qo'shiladi.
  - Tezlik/parallellik: token bucket (120, 40/s); **kadr 10 token turadi va yuborilgan intervalning yarmidan tez
    kelmaydi** (`429 too_fast`); bitta token bir vaqtda 4 so'rov, bitta IP 16 so'rov (`429 too_many_requests`);
    global 128 so'rov — lekin autentifikatsiyalangan `/keepalive`, `/ping`, `/leave` va `/health` bu limitdan
    ozod; `lastSeen` autentifikatsiya muvaffaqiyatida, har qanday limitdan OLDIN yangilanadi (hujum qurbonni
    "aloqa yo'q" qila olmaydi). `/join`: IP bo'yicha bir vaqtda 4 ta.
  - 60 klient, bitta IP'dan 8 tagacha. Incident/clock flag ro'yxatlari serverning 201/101, 1 KiB, 48 KiB
    chegarasiga qisqartiriladi (ortig'i `*_overflow` hisoblagichiga).
  - Kadr: faqat JPEG. O'lcham **dekodsiz** olinadi va **kodekning o'zidan** (`ui.ImageDescriptor.encoded` — faqat
    sarlavha, real 10000x10000 ~1 MB RSS) — qo'lda yozilgan sarlavha o'qigichni ikkinchi (soxta) SOF aldashi mumkin
    edi (N-1). Tomoni > 4096 yoki > 8 MP bo'lsa `422 frame_too_large`; kodek tushunmasa/sarlavha buzuq/ikkita SOF
    bo'lsa `400 bad_frame`. `jpegSize` ikkinchi chiziq (arzon, hech qachon xato tashlamaydi: fill-byte, qisqa fayl).
    O'qituvchi ekrani `Image.memory(cacheWidth: 960)` bilan chizadi.
- **Idempotentlik:** kalit payload'ga bog'langan: bir xil kalit + bir xil tana → ack; bir xil kalit + boshqa tana →
  `409 idempotency_conflict` (klientda "rad etilgan" deb saqlanadi, yo'qolmaydi).
- **Xato javoblari** faqat barqaror kod (`{"error": "..."}`); stack, yo'l, PIN, kalit, kod, token yo'q.
  Loglarda token/kod/PIN yo'q.
- **Ekran kadrlari** faqat hub xotirasida (har PC uchun oxirgi *keyframe*), diskka yozilmaydi; test tugasa,
  hub to'xtasa yoki paket yopilsa o'chadi. Patch kadrlar saqlanmaydi (hub rasm yig'maydi); ko'rilayotgan
  o'quvchidan har javobda `request_keyframe` so'raladi.
- **Bir o'quvchi — ikki PC (o'rin to'qnashuvi):** ikkinchi PC `conflict: true` oladi (mavjud "boshqa qurilmada"
  xabari). Birinchi PC **hech qachon o'z-o'zidan to'xtatilmaydi** — qancha jim bo'lmasin (aks holda hujumchi o'rinni
  "oldindan band qilib", qurbon aloqasi uzilganda o'rinni olib, uning testini majburan yakunlatardi). O'qituvchi
  ekranida to'qnashuv banneri chiqadi (o'quvchi, ikkala PC nomi/IP): **"Yangisini rad et"** (asosiy tugma; 5 daqiqa
  rad etiladi, banner qayta chiqmaydi) yoki **"Eskisini bo'shat"** (kamroq ta'kidlangan: eskisiga `terminated`
  boradi). Bo'shatilgach o'rin **60 soniya faqat o'qituvchi ko'rgan da'vogar uchun saqlanadi** (boshqa token/PC
  birinchi bo'lib ping qilsa ham olmaydi); muddat tugasa bo'shaydi. Banner o'quvchi ismi va ikkala tomonning
  qurilma nomi, IP, qancha vaqt oldin ulangani va holatini ko'rsatadi; ko'pi bilan 3 ta banner + "+N" hisoblagich,
  balandligi cheklangan va aylanadi. Bitta IP'dan ochiq to'qnashuvlar 4 tadan oshmaydi.
- **`machine_id`:** o'rnatishga tasodifiy UUID (birinchi ishga tushishda yaratilib `shared_preferences`da
  saqlanadi; Windows `MachineGuid` ishlatilmaydi — klonlangan lab image'larida bir xil). Hub eski klientni
  almashtirish uchun `machine_id` **va** IP ikkalasi mos kelishini talab qiladi; almashtirishda terminated/ended
  attempt'lar, o'rin, hisoblagichlar **va to'xtatish (pauza) hamda berilgan qo'shimcha vaqt** yangi klientga ko'chadi
  (qayta join o'quvchining pauzasini yechmaydi, berilgan vaqtni qaytarib olmaydi).
- **Qo'shilishni yopish:** o'qituvchi hamma ulangach tugmani bosadi → `/join` `403 joins_locked` (kod tekshirilmaydi,
  xato hisoblagichlariga tegilmaydi). Noto'g'ri kodlar oqimi (har IP'dan 5 xato / global 60 xato) yangi
  ulanishlarni 1 daqiqaga bloklashi mumkin; yopilgan hubda bu ahamiyatsiz. Yaroqli tokenli PC o'sha mashinaning
  qayta join'ida global blok va yopiqlikdan o'tadi.
- **Ulanishni tasdiqlash:** kod to'g'ri bo'lgach o'quvchi PC rejimga o'tishdan OLDIN "paket izi" (`pack_uuid`dan
  olingan 6 belgi) va hub nomini ko'radi; o'qituvchi ekranida ham shu iz turadi. UDP e'londa `pack_uuid` yo'q
  (shu qaror saqlanadi) — iz faqat tasdiqlangan `join` javobidan olinadi. Discovery ro'yxatida bitta manba IP'ga
  4 tadan ko'p yozuv qo'shilmaydi.
- **Ulanishni tasdiqlash tugamasa:** dialog "Ha"/"Yo'q"siz yopilsa (Esc, oyna almashishi) tasdiqlanmagan sessiya
  `/leave` yuboradi — hub'da "arvoh" klient qolmaydi.
- **Eski hub tokeni:** qayta ulanishda `Authorization: Bearer` (global blok/qulfdan o'tish uchun) faqat eski hub'ning
  AYNAN o'sha host va portiga yuboriladi; tanlangan/qo'lda kiritilgan boshqa manzilga (rogue hub) hech qachon, va
  javobdagi redirect orqali ham emas.
- **Klient javoblari:** `pack_uuid` qat'iy UUID; `join` javobi <= 64 KB, JSON <= 4 MB (test/diagnostika/paket
  savollari <= 32 MB), rasm <= 16 MB; oshsa uziladi. Hub to'lgan (`pack_full`/`client_quota`) bo'lsa natija
  o'chmaydi va "rad etilgan" ham bo'lmaydi: navbatda qoladi, sekin (5 daqiqa) qayta uriniladi, operatorga
  "o'qituvchiga murojaat qiling" ko'rsatiladi.

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

## O'qituvchi uchun tartib (kod chiqib ketsa)

1. **Kodni yangilash** mavjud tokenlarni bekor QILMAYDI — faqat yangi ulanishlar uchun yangi kod kerak bo'ladi.
2. Keraksiz PC'ni **uzish (kick)** tokenini bekor qiladi, lekin u kodni bilsa qayta join qila oladi.
3. Shuning uchun tartib: avval kodni yangilang, keyin keraksiz PC'ni uzing, so'ng **Qo'shilishni yopish**ni bosing
   (yopiq hubda hech kim, kodni bilsa ham, qayta join qila olmaydi).

## Hujjatlangan, qilinmagan (T2 review INFO)

- **N-7** — paket izi (fingerprint) 24 bit (`sha256` ning 6 hex belgisi). Bu "noto'g'ri xona" tekshiruvi (o'quvchi
  boshqa o'qituvchi hub'iga ulanib qolmasligi uchun), **autentifikatsiya EMAS**: sinf kodi iz tasdiqlanishidan OLDIN
  yuboriladi, ya'ni rogue hub kodni ko'radi. Iz hujumchini to'xtatmaydi, faqat halol xatoni ushlaydi.

- **S-012** — klient yuborgan incident'lar hub tomonidan tekshirib bo'lmaydi (faqat shakl/hajm); ular metadata,
  ball emas.
- **S-013** — butun roster va testlar ulangan har bir klientga ochiq. Guruh bo'yicha tekshiruv qo'shilmadi: guruh
  id'lari `/groups` da ochiq, shuning uchun hujumchi uchun foydasi yo'q, halol oqim esa buzilishi mumkin.
- **S-015** — NAT ortidagi bir manzildan ko'p PC ulansa, manzil bo'yicha kvota/parallellik/8-klient chegarasi
  ularni birga cheklaydi. Sinf tarmog'ida NAT bo'lmasligi kerak.
