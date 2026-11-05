# LAN Hub — ma'lum cheklovlar (qisqacha)

Kod o'zgartirilmagan, bu hujjat faqat hozirgi holatni qayd etadi. To'liq xavfsizlik modeli: `offline_lan_hub.md`.
Manba: `lib/core/local_server/shelf_hub.dart`, `hub_guard.dart`, `hub_state.dart`;
klient: `lib/core/offline/lan_client_session.dart` (`Uri(scheme: 'http', ...)`).

## 1. HTTP, TLS yo'q

Hub oddiy HTTP (`shelf_io.serve`, `InternetAddress.anyIPv4`). Sinf kodi (`POST /join` tanasida) va bearer token
(`Authorization` sarlavhasi) shu LAN segmentini tinglay oladigan har kimga ochiq ko'rinadi. Token ko'chirib
olinsa, egasi o'sha PC nomidan so'rov yubora oladi.

## 2. Token manba IP'ga bog'lanmagan

Token `Random.secure()` dan 32 bayt (base64url). Klient yozuvi (`HubClient`) `machine_id` va `ip` ni join paytida
saqlaydi, lekin `HubState.authenticate(token)` tokenni faqat `_byToken` xaritasidan qidiradi (`_byToken[token]`):
so'rov qaysi IP'dan kelgani tekshirilmaydi. `machine_id` + IP faqat bir PC'ning qayta join'ida eski yozuvni
almashtirish uchun ishlatiladi.

## 3. Sinf kodi va noto'g'ri urinishlar

- Kod: 6 ta tasodifiy raqam (`nextInt(1000000)`, `Random.secure()`), taqqoslash doimiy vaqtda.
- Bitta IP'dan 5 ta noto'g'ri kod (`maxFailures = 5`) shu IP'ni 60 soniyaga (`blockMs = 60000`) bloklaydi.
- Global yuqori chegara: istalgan manzillardan 60 ta noto'g'ri kod (`globalMaxFailures = 60`) so'nggi 60 soniya
  ichida bo'lsa, HAMMA yangi join'lar 60 soniyaga bloklanadi. Demak noto'g'ri kodlar oqimi halol o'quvchilarning
  qo'shilishini bir daqiqaga kechiktirishi mumkin. Yaroqli tokenli PC (qayta join) global blokdan o'tadi.
- IP bo'yicha xato hisobi 10 daqiqa jim turgach unutiladi; vaqt monotonik soat bilan o'lchanadi.

## 4. Bugun mavjud yumshatishlar

- **Qo'shilishni yopish** (join lock): hamma ulangach bosiladi; yopiq hub kodni tekshirmaydi ham, xato
  hisoblagichlariga ham tegmaydi.
- Faqat ishonchli LAN: izolyatsiyalangan sinf tarmog'i; o'quvchilar bilan umumiy Wi-Fi'da ishlatmang.
- Kod sizib chiqsa: **Kodni yangilash** (mavjud tokenlarni bekor qilmaydi), keyin keraksiz PC'ni uzing
  (kick tokenni bekor qiladi), so'ng qo'shilishni yoping.

## 5. Qachon qayta ko'rish kerak

- Hub ishonchsiz yoki umumiy tarmoqda ishlatilsa: o'z-o'zidan imzolangan sertifikatli TLS (klientda sertifikat
  pinlash) — kod va token yashirinadi.
- Token manba IP'ga bog'lansa (`authenticate` IP'ni ham solishtirsa) — o'g'irlangan token boshqa PC'dan ishlamaydi
  (NAT ortidagi PC'lar va IP o'zgarishini hisobga olish kerak, qarang S-015).
