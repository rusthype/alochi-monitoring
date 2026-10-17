# Oflayn rejim — Windows E2E runbook (odam bajaradi)

CI (`offline-windows-verify.yml`) Windows'da kod va testlarni tekshiradi, lekin **GUI'ni, ikki PC'li LAN'ni,
Windows Firewall so'rovini, uyqu/hibernatsiyani isbotlamaydi**. Shu hujjat o'sha bo'shliqni yopadi.
Har qadamda natijani katakka yozing: `[ ]` -> `[x] o'tdi` yoki `[!] yiqildi` + izoh.

> **Build FAQAT SINOV:** test kalitlari bilan yig'ilgan, imzosiz; test kalitlarining private qismi ommaviy
> repoda. Maktab kompyuterlariga o'rnatmang, sinovdan keyin o'chiring.

## 0. Tayyorgarlik

**Kerak:** 1 ta Windows 10/11 PC (Senariy 1, 2, 4); LAN uchun 2 ta Windows PC, bitta tarmoqda (Senariy 3);
1 ta USB flesh; 1 ta Mac (natijani tekshirish uchun).

1. **Build olish** (Mac'da, `gh` avtorizatsiyalangan):
   ```bash
   gh run list --repo rusthype/alochi-monitoring --branch feat/offline-usb-pack --limit 5
   gh run download <RUN_ID> --repo rusthype/alochi-monitoring -n alochi-monitoring-offline-TEST-ONLY-<sha7>
   ```
   Yoki brauzerda: GitHub -> Actions -> "Offline Windows verify" -> run -> **Artifacts**. Artifact 3 kun
   saqlanadi (retention). Zip'ni oching, ichida `alochi_monitoring.exe` va `README_TEST_ONLY.txt`.
   Butun papkani PC'ga ko'chiring (faqat `.exe` emas — DLL'lar kerak).
2. **Birinchi ishga tushirish:** imzosiz bo'lgani uchun SmartScreen chiqadi: "More info" -> "Run anyway".
   Login ekranida **"Oflayn rejim"** tugmasi ko'rinishi kerak. "Oflayn rejim bu o'rnatishda sozlanmagan"
   chiqsa — build kalitsiz yig'ilgan, to'xtang va yozib qo'ying.
3. **Test paketi:** `test/fixtures/offline/golden.alochipack` (shu repo) — **PIN `12345678`**, maktab `999`,
   guruh `5-A | Ingliz`, **bitta** o'quvchi `Golden O'quvchi` (`G-0001`), test `Golden` (5 savol, 30 daqiqa),
   amal qilish muddati 2099. Backend nusxasi:
   `/Users/max/PycharmProjects/AlochiSchool/alochi/.claude/worktrees/agent-ab638607e6e37ee92/alochi_backend/apps/monitoring/tests/fixtures/offline/golden.alochipack`.
   Faylni USB flesh orqali PC'ga ko'chiring (tarmoq orqali emas).
4. **Natijani tekshirish (Mac):** `pip install cryptography` bo'lishi kerak.
   ```bash
   cd /Users/max/PycharmProjects/AlochiSchool/alochi/.claude/worktrees/agent-ab638607e6e37ee92/alochi_backend
   F=apps/monitoring/tests/fixtures/offline
   python3 -I $F/verify_alochires.py <fayl.alochires> $F/test_results_private.pem 12345678 --pack $F/golden.alochipack
   echo "exit=$?"
   ```
   Argumentlar: `.alochires` fayl, natija **private** kaliti, PIN, `--pack` (zanjir tuzi shundan olinadi; usiz
   `chain_verified` doim `false`). Chiqish: JSON. **exit 0 va `"chain_verified": true`** — yaxshi.
   exit 2 -> `{"rejected": "<sabab>"}` — yiqildi (sababni yozing). Skript backend papkasidan ishga tushiriladi.
5. **Windows Firewall:** LAN senariyda o'qituvchi PC'da hub birinchi yoqilganda so'rov chiqadi (TCP 8080),
   o'quvchi PC'da UDP 8081 tinglash uchun ham chiqishi mumkin. Aynan nima chiqqanini yozing (3-senariy, 6-bo'lim).
6. Har senariy oldidan: ilovani to'liq yoping (Task Manager'da `alochi_monitoring.exe` yo'qligini tekshiring).

---

## Senariy 1 — USB, tarmoqsiz (kriteriy 1, 3)

Tayyorlik: Wi-Fi va Ethernet **o'chirilgan** (Airplane mode). PC'da `golden.alochipack` bor.

| # | Amal | Kutilgan natija | Natija |
|---|------|-----------------|--------|
| 1.1 | Ilovani oching, login ekranida **"Oflayn rejim"** | Dialog "Oflayn rejim", "Paket ochilmagan" | [ ] |
| 1.2 | **"Paket yuklash (.alochipack)"** -> `golden.alochipack` | "Paket PIN-kodi" so'raydi | [ ] |
| 1.3 | PIN `12345678` -> **"Ochish"** | "Paket ochilmoqda..." keyin guruh tanlash ekrani; xato yo'q | [ ] |
| 1.4 | Noto'g'ri PIN (`00000000`) bilan sinab ko'ring (1.2 ni qaytaring) | "PIN noto'g'ri." | [ ] |
| 1.5 | **"Guruhni tanlang"** -> `5-A \| Ingliz` -> **"O'quvchini tanlang"** -> `Golden O'quvchi` | Test ro'yxati: `Golden` | [ ] |
| 1.6 | Testni boshlang, 5 savolni yeching (taymer yurishini kuzating) | Taymer kamayadi, rasmli savol (image_choice) rasmni ko'rsatadi | [ ] |
| 1.7 | Testni tugating | **"Javoblaringiz saqlandi"** — **ball ko'rsatilmaydi** | [ ] |
| 1.8 | Login ekrani -> "Oflayn rejim" | "Saqlangan: 1 · Eksport qilinmagan: 1" | [ ] |
| 1.9 | **"Natijalarni eksport (.alochires)"** -> flesh papkasi | "Eksport qilindi: 1 ta natija (...alochires)"; keyin "Eksport qilinmagan: 0" | [ ] |
| 1.10 | Fleshni Mac'ga o'tkazing, 0-bo'lim 4-qadamdagi buyruq | exit 0, `chain_verified: true`, `entries` ichida bitta yozuv, `payload.student_id` = `...0d4` | [ ] |
| 1.11 | Ilovani yoping, qayta oching, "Oflayn rejim" | Saqlangan natija yo'qolmagan (1.8 dagidek) | [ ] |

Yozib qo'ying: eksport fayl nomi, `chain_tip`, 1.7 da haqiqatan ball ko'rinmaganini (skrinshot).

---

## Senariy 2 — soatni qalbakilashtirish (kriteriy 4)

Tayyorlik: Senariy 1 dagidek paket ochiq, **Windows sanasi/vaqtini qo'lda o'zgartira oladigan** admin hisob.
"Set time automatically" o'chirilgan (Settings -> Time & language -> Date & time).

| # | Amal | Kutilgan natija | Natija |
|---|------|-----------------|--------|
| 2.1 | Testni boshlang (30 daqiqa). Taymerdagi qolgan vaqtni yozing: `T0 = ____` | — | [ ] |
| 2.2 | ~1 daqiqadan keyin Windows soatini **+1 soat oldinga** o'zgartiring | Taymer **sakramaydi** (faqat haqiqiy o'tgan vaqt kamayadi), test **bloklanmaydi** | [ ] |
| 2.3 | ~1 daqiqa kuting, soatni **90 daqiqa orqaga** suring (natijada haqiqiy vaqtdan **30 daqiqa orqada**) | Taymer yana sakramaydi, test davom etadi | [ ] |
| 2.4 | Skew tekshiruvi har 5 s da ishlaydi — 10 s kuting | UI'da ogohlantirish chiqmasligi **normal** (qaror 8: faqat belgi, bloklash yo'q) | [ ] |
| 2.5 | Testni tugating, soatni **avtomatik** holatga qaytaring | "Javoblaringiz saqlandi" | [ ] |
| 2.6 | Eksport + `verify_alochires.py` (1.9-1.10) | `entries[0].clock_flags` ichida `clock_forward` (`skew_ms` ~ +3 600 000) va `clock_backward` (`skew_ms` ~ -5 400 000) | [ ] |
| 2.7 | `chain_verified` | `true` | [ ] |

`clock_flags` chiqishda shunday ko'rinadi (har biri: `type`, `skew_ms`, `wall_delta_ms`, `monotonic_delta_ms`,
`wall_utc`, `trusted_utc`):
```json
"clock_flags": [ {"type": "clock_forward", "skew_ms": 3600xxx, ...}, {"type": "clock_backward", "skew_ms": -5400xxx, ...} ]
```
Boshqa mumkin turlar: `clock_before_high_water_mark` (soat ilgari ko'rilgan eng katta vaqtdan orqada — keyingi
test boshlanganda tekshiriladi), `clock_before_pack_created`, `clock_flags_overflow`.

> Eslatma: asl hujjat (4-kriteriy) "bloklash"ni so'ragan; amalda **qaror 8** — faqat metadata, bloklanmaydi.
> Shu senariy aynan shuni tasdiqlaydi; farqni hisobotda ayting.

### 2B. Uyqu / hibernatsiya (OCHIQ SAVOL — tajriba)

Noma'lum: Windows'da `GetTickCount64` kompyuter uyquda turgan vaqtni sanaydimi? Agar sanamasa, qopqoqni yopgan
o'quvchi testga qo'shimcha vaqt oladi (kodda hujjatlangan cheklov, `monitored_clock.dart`).

1. Yangi test boshlang, taymer: `A = ____` (soat: `__:__:__`).
2. Noutbuk qopqog'ini yoping (yoki Start -> Sleep) va **aniq 3 daqiqa** kuting (sekundomer bilan).
3. Oching, tizimga qayting. Taymer: `B = ____` (soat: `__:__:__`).
4. Hisob: devor soati farqi `W = ____` (taxminan 3 daqiqa+), taymer farqi `A - B = ____`.
   - `A - B` ~ `W` -> uyqu vaqti sanaladi (xavf yo'q).
   - `A - B` ~ 0 -> uyqu vaqti **sanalmaydi** (o'quvchi vaqt yutadi).
5. Testni tugating, eksport qiling: uyqudan keyin `clock_forward` belgisi (taxminan 3 daqiqa) paydo bo'ldimi? `[ ] ha  [ ] yo'q`
6. Qo'shimcha: Hibernate (`shutdown /h`) bilan ham takrorlang. Natijani yozing: `Sleep: ______  Hibernate: ______`.
7. Modern Standby (S0) va klassik S3 farqlanishi mumkin: `powercfg /a` chiqishini ilova qiling.

---

## Senariy 3 — LAN, 2 PC (kriteriy 2, 3)

Tayyorlik: ikkala PC **bir tarmoqda** (bitta router/switch, internet kerak emas), ikkala PC'da build.
**O'qituvchi PC** (T) va **o'quvchi PC** (S). Paket faqat T'da. Roster'da bitta o'quvchi bor (`Golden O'quvchi`);
ikkinchi o'quvchi PC bo'lsa, o'rin to'qnashuvi bannerini tekshirish imkonini beradi (3.14).

| # | PC | Amal | Kutilgan natija | Natija |
|---|----|------|-----------------|--------|
| 3.1 | T | "Oflayn rejim" -> **"Lokal server yoqish (LAN)"** -> paket -> PIN | "Sinf monitoringi (LAN)" ekrani ochiladi, server avtomatik yonadi: "Server ishlayapti", `Manzil: IP:port` | [ ] |
| 3.2 | T | Windows Firewall so'rovi chiqsa: **Private** tarmoqqa "Allow access". Nima chiqqanini yozing | — | [ ] |
| 3.3 | T | **Sinf kodi** (6 raqam) ko'rinadi; IP'ni yozib oling: `____` | — | [ ] |
| 3.4 | S | "Oflayn rejim" -> **"O'qituvchi kompyuteriga ulanish"** | "Topilgan kompyuterlar" ro'yxatida T ko'rinadi (UDP). Ko'rinmasa: "Hech narsa topilmadi..." — IP:port ni **qo'lda** kiriting ("Yoki manzilni qo'lda kiriting", masalan `192.168.1.5:8080`). Qaysi yo'l ishlaganini yozing | [ ] |
| 3.5 | S | Sinf kodini kiriting -> **"Ulanish"** | **"Ulanishni tasdiqlang"**: hub nomi va "Paket izi" (6 belgi) | [ ] |
| 3.6 | T | Monitoring ekranida "Paket izi" | S dagi bilan **bir xil** | [ ] |
| 3.7 | S | **"Ha, davom etish"** | "Ulangan kompyuter: ..." + "Testlarni boshlash" | [ ] |
| 3.8 | T | Ro'yxat | "Ulangan: 1 / 60", S kompyuter holati "Kutmoqda" | [ ] |
| 3.9 | S | "Testlarni boshlash" -> guruh -> o'quvchi -> `Golden` testini boshlang | T da holat "Testda", **"Savol N/5"**, **"Oynadan chiqish: n"**, kadr (ekran tasviri) ko'rinadi | [ ] |
| 3.10 | S | Test paytida boshqa oynaga o'ting (Alt+Tab) 2-3 marta | T da "Oynadan chiqish" soni oshadi | [ ] |
| 3.11 | T | O'quvchini tanlang -> **"Pauza"** | S da test to'xtaydi (qulf); **"Davom ettirish"** bilan qaytadi | [ ] |
| 3.12 | T | **"+1 daqiqa"**, so'ng **"+5 daqiqa"** | S taymeri mos ravishda oshadi (jami +6) | [ ] |
| 3.13 | T | **"Kodni yangilash"** | Yangi kod; S ulanishi uzilmaydi ("Allaqachon ulangan kompyuterlar uzilmaydi") | [ ] |
| 3.14 | T | **"Qo'shilishni yopish"** | "Qo'shilish yopiq..."; S yoki 3-PC yangi ulanishda "O'qituvchi yangi ulanishlarni yopgan." Keyin **"Qo'shilishni ochish"** | [ ] |
| 3.15 | S | **Outbox sinovi:** testni tugatishdan OLDIN T'da **"Serverni to'xtatish"** (yoki T ilovasini yoping) | S da "Aloqa yo'q — natijalar saqlanmoqda..." | [ ] |
| 3.16 | S | Testni tugating (hub o'chiq) | "Javoblaringiz saqlandi"; "Yuborilmagan natijalar: 1" | [ ] |
| 3.17 | T | Serverni qayta yoqing (T ilovasi yopilgan bo'lsa — paketni PIN bilan qayta oching; **yangi sinf kodi** bo'ladi, eski tokenlar bekor) | S qayta ulanadi (kerak bo'lsa yangi kod), yuborilmagan natija **ack** bo'ladi, T da "Qabul qilingan natijalar: 1" | [ ] |
| 3.18 | T | **"Testni yakunlash"** (boshqa, hali tugamagan test uchun) -> "Yakunlash" | S testi yakunlanadi, javoblar saqlanadi | [ ] |
| 3.19 | T | **"Natijalarni eksport (.alochires)"** (monitoring ekranidan yoki "Oflayn rejim" dialogidan) -> flesh | Butun sinf uchun **bitta** `.alochires` | [ ] |
| 3.20 | Mac | `verify_alochires.py` | exit 0, `chain_verified: true`; `entries` ichida har S natijasi bir marta (dublikat yo'q); `incidents` ichida `focus_lost`/`focus_regained` | [ ] |
| 3.21 | 3-PC (ixtiyoriy) | Xuddi shu o'quvchi nomidan ulaning | T da "O'rin to'qnashuvi" banneri: "Yangisini rad et" / "Eskisini bo'shat" | [ ] |

Yozib qo'ying: UDP orqali topildimi yoki qo'lda IP kerak bo'ldimi; Firewall oynasi qaysi PC'da chiqdi va nima
deyildi; ping/kadr kechikishi (taxminan, soniya).

---

## Senariy 4 — ilovaga qotirilgan ("assets") testlar (kriteriy 1)

Tayyorlik: Senariy 1 yoki 3 dagidek paket ochiq (USB) yoki hub'ga ulangan (LAN S). Tarmoq o'chiq.

Kirish nuqtalari (login ekranida): **"Oddiy kirish (Internet kerak emas)"** (Interhouse Grade 2 / lokal baholash)
va **"Monitoring Test Unit 1"** (Combined: Unit 1 + Bob 1-4). Bu kirish ekranlarida ism maydonlari o'rniga
**guruh -> o'quvchi** tanlash chiqishi kerak; tanlanmaguncha test boshlanmaydi.

| # | Test | Amal | Kutilgan | Natija |
|---|------|------|----------|--------|
| 4.1 | Interhouse (Oddiy kirish) | Guruh/o'quvchi tanlang, variantni boshlang, tugating | Ball ko'rsatilmaydi: "Javoblaringiz saqlandi" | [ ] |
| 4.2 | Combined / Unit 1 / Bob 1-4 (Monitoring Test Unit 1) | Xuddi shunday | "Javoblaringiz saqlandi" | [ ] |
| 4.3 | Local test (lokal baholash) | Xuddi shunday | "Javoblaringiz saqlandi" | [ ] |
| 4.4 | O'quvchi tanlanmasa | Boshlashga urinib ko'ring | Test boshlanmaydi | [ ] |
| 4.5 | — | "Oflayn rejim" dialogini oching | "Saqlangan" soni topshirilgan testlar soniga teng | [ ] |
| 4.6 | Eksport + `verify_alochires.py` | `payload.test_key` va `payload.detail.test_key` ichida `asset:unit1_eng`, `asset:monitoring_unit1`, `asset:interhouse_g2`, `asset:bob1_4` (qaysi test o'tgan bo'lsa shu) | exit 0, `chain_verified: true` | [ ] |

Eslatma: alohida `Unit 1` va `Bob 1-4` ekranlariga login ekranidan to'g'ridan-to'g'ri tugma yo'q (faqat Combined
ichida); `asset:unit1_eng` / `asset:bob1_4` kalitlari qaysi yo'l bilan paydo bo'lishini 4.6 da yozib qo'ying.

---

## 5. Ochiq savollar — nima yozib olish kerak

| # | Savol | Qanday aniqlanadi | Yozib olinadigan ma'lumot |
|---|-------|-------------------|----------------------------|
| Q1 | `GetTickCount64` uyqu/hibernatsiya vaqtini sanaydimi | Senariy 2B | `A`, `B`, `W`; `powercfg /a`; uyqudan keyingi `clock_forward` bor/yo'q; Windows versiyasi |
| Q2 | UDP broadcast boshqa subnet niqoblarida (masalan `/16`, `/23`) | 3.4 ni `255.255.255.0` bo'lmagan tarmoqda takrorlang (`ipconfig` -> Subnet Mask). Hub e'loni `255.255.255.255` va `a.b.c.255` ga yuboriladi | Niqob, T va S IP'lari, avtomatik topildimi / faqat qo'lda IP ishladimi |
| Q3 | Firewall **Public** profili | T tarmog'ini Public qiling (Settings -> Network -> Properties -> Network profile type = Public), hub'ni qayta yoqing, S dan ulaning (3.4-3.5) | So'rov chiqdimi; Public'da inbound bloklanib S ulana olmadimi; "Allow" qaysi profillar uchun tanlandi |
| Q4 | O'quvchi PC'da UDP 8081 uchun Firewall so'rovi | S da 3.4 | So'rov chiqdimi; "Block" bosilsa — qo'lda IP ishlaydimi (ishlashi kerak) |
| Q5 | CI'dagi `INFO-WINDOWS` kuzatuvlari | Actions run -> Summary | `255.255.255.255` broadcast hosted runner'da ishladimi (bu real tarmoq emas) |
| Q6 | Ikkinchi bir xil port UDP bind | CI summary | `reuseAddress` bilan ikkinchi bind natijasi |

---

## 6. Yakuniy qabul jadvali

Asl hujjat: `/Users/max/PycharmProjects/AlochiSchool/alochi/docs/PROMPT_OFFLINE_ZERO_INTERNET_TESTING_SYSTEM.md`,
"КРИТЕРИИ ПРИЁМКИ".

| Kriteriy | Qaysi senariy | Qabul sharti | Holat |
|----------|---------------|--------------|-------|
| **1.** Internetsiz: yuklangan `.alochipack` bilan o'quvchi tanlaydi, testni taymer bilan topshiradi, lokal natija oladi | **S1** (1.1-1.11), **S4** | Tarmoq o'chiq; 1.3, 1.5-1.7 o'tdi. Eslatma: "lokal natija" amalda "Javoblaringiz saqlandi" (ballsiz, qaror 2) | [ ] |
| **2.** LAN Hub: o'qituvchida "Lokal server", o'quvchida ulanish UDP orqali avtomatik; sinxron test; o'qituvchi ekranida jonli progress; natijalar o'qituvchi PC'da | **S3** (3.1-3.20) | 3.4 (UDP topildi), 3.9-3.12 (jonli progress, pauza, +vaqt), 3.16-3.17 (outbox), 3.19 | [ ] |
| **3.** Eksport/import: yig'ilgan natijalar valid `.alochires`; backend dublikatsiz saqlaydi | **S1** (1.9-1.10), **S3** (3.19-3.20), **S4** (4.6) | `verify_alochires.py` exit 0 + `chain_verified: true`, dublikat yo'q. Backend `import-results` endpointiga haqiqiy yuklash bu runbookdan tashqari (backend repo) | [ ] |
| **4a.** Soat qalbakilashtirish aniqlanadi | **S2** (2.2-2.7), **2B** | `clock_forward` va `clock_backward` eksportda. Hujjat "bloklash" so'ragan, amalda **faqat belgi** (qaror 8) — farqni qayd eting | [ ] |
| **4b.** Savollar bazasi shifrlangan, ochiq javob yo'q | **S1** (1.3-1.4) + qo'lda | Noto'g'ri PIN rad etiladi (1.4). Qo'shimcha: paket fayli (zip) ichida `content.json.enc` ochiq matn emas (`7z`/`unzip -l`) | [ ] |
| **5.** Sifat: `flutter analyze` 0 xato | CI | `offline-windows-verify` "Flutter analyze" yashil | [ ] |

Natija bo'yicha qaror: barcha qatorlar `[x]` bo'lsa — oflayn rejim Windows'da qabul qilinadi; istalgan `[!]` — sababi
bilan birga Actions run ID, build SHA (`README_TEST_ONLY.txt`), PC modeli va Windows versiyasini ilova qiling.
