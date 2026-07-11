# Alochi Monitoring — macOS'da o'rnatish

## Tavsif

Alochi Monitoring — O'zbekistondagi maktablarda o'quvchilarni test qilish tizimi uchun macOS dasturi. U o'qituvchilar va adminlarni real vaqtda test jarayonini kuzatishga yordam beradi.

---

## O'rnatish

1. **DMG faylni yuklab oling:**
   - https://github.com/rusthype/alochi-monitoring/releases/tag/latest sahifasiga boring
   - `alochi-monitoring.dmg` faylni yuklab oling

2. **O'rnatishni boshlang:**
   - Yuklab olingan `.dmg` faylni ikki marta bosing — disk tasviri ochiladi
   - Ochilgan oynada **Alochi Monitoring** ilovasini **Applications** papkasi belgisiga torting (drag & drop)

3. **Dasturni ishga tushiring:**
   - Applications papkasini oching, **Alochi Monitoring**ni toping

---

## "Damaged file" / Gatekeeper xatosi chiqsa

Dastur **ad-hoc imzolangan** (Apple Developer sertifikati bilan emas), shuning uchun oddiy ikki marta bosish macOS 15+ da "Alochi Monitoring" is damaged and can't be opened" degan xato berishi mumkin. Bu xato yo'q — GitHub'dan to'g'ri yuklab olingan fayl xavfsiz.

**Birinchi ishga tushirishda:**
1. Applications papkasida **Alochi Monitoring** ustida **o'ng tugma bosing** (yoki Control bosib turib bosing)
2. Paydo bo'lgan menyudan **Open** ni tanlang
3. Chiqqan tasdiq oynasida yana **Open** ni bosing

Shundan keyin dastur oddiy bosish orqali ham ochiladi.

---

## O'rnatishni o'chirish

1. Applications papkasini oching
2. **Alochi Monitoring** ilovasini Trash'ga torting
3. Trash'ni bo'shating

---

## Yangilash

Alochi Monitoring avtomatik yangilanmaydi (Windows versiyasi kabi — ilova ochilganda yangi versiya bor-yo'qligi haqida bildirishnoma ko'rsatiladi, lekin yuklab olish/o'rnatish qo'lda amalga oshiriladi). Yangi versiya chiqsa:

1. Eski `.app` faylni Applications papkasidan Trash'ga o'chiring (yuqorida aytilganidek)
2. Yangi `.dmg` ni yuklab oling va o'rnatishni qayta boshlang

---

## Muammolar

### Dastur ochilmaydi, hech qanday xato ham chiqmaydi
- **System Settings → Privacy & Security** ni oching, pastda "Alochi Monitoring" bloklangani haqida xabar bo'lsa, **Open Anyway** ni bosing

### Boshqa savol
- GitHub issues sahifasida savol bering: https://github.com/rusthype/alochi-monitoring/issues

---

*Oxirgi yangilanish: 2026-yil iyul*
