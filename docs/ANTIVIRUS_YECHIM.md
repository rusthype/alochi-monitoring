# Virusni Aniqlash Muammolarini Hal Qilish / Antivirus False Positive Solutions

Agar siz Alochi Monitoring dasturini o'rnatishda Windows Defender, SmartScreen yoki boshqa antiviruslar tomonidan ogohlantirish olsangiz, bu faylda berilgan qadam-bo'yama yo'riqnomalarni bajaring.

> **Eslatma:** Alochi Monitoring — zararsiz, açiq manba Flutter dasturi. Ogohlantirish faqat dastur imzosi yangi bo'lgani (o'rnatilmagan sertifikat) va yuqori takrorlanmasligi sababli chiqadi. Yuklama ortib, lokal reputatsiya ortdikdan keyin ogohlantirish yo'qoladi.

---

## 1. Windows SmartScreen Ogohlantirishi

**Holatlar:**
- "Windows protected your PC" (Inglizcha)
- "Windows sizning kompyuteringizni himoya qildi" (O'zbekcha)

### Qadam-bo'yama

1. **Ogohlantirish oynasi paydo bo'ladi. "More info" tugmasini bosing** (inglizcha) yoki **"Qo'shimcha ma'lumot" tugmasini bosing** (O'zbekcha).

2. **Yoqangi oyna paydo bo'ladi, oxirida "Run anyway" (inglizcha) yoki "Baribir ishga tushirish" (O'zbekcha) tugmasi ko'rinadi. Uni bosing.**

3. Dastur o'rnatilishni boshlaydi.

**Rasm:**
```
┌─────────────────────────────────────────┐
│ ⚠️  Windows protected your PC            │
│                                         │
│ SmartScreen prevented an unrecognized   │
│ app from starting. Running this app     │
│ might put your PC at risk.              │
│                                         │
│ [More info]              [Don't run]    │
└─────────────────────────────────────────┘

Keyin:

┌─────────────────────────────────────────┐
│ ⚠️  App has unrecognized publisher       │
│                                         │
│ Publisher: Unknown                      │
│ App: AlochiMonitoring-Setup.exe         │
│                                         │
│ [Run anyway]             [Cancel]       │
└─────────────────────────────────────────┘
```

---

## 2. Windows Defender Istisno Qo'shish

Antivirusga Alochi Monitoring papkasini ishonchli deb berish uchun:

### Qadam-bo'yama

1. **Settings (Sozlamalar) aç → Search ichida "Windows Security" yoz.**

2. **Windows Security (Windows Xavfsizligi) ilovasini aç.**

3. **Left sidebar-da "Virus & threat protection" (Virus va Tahdid Himoyasi) bosing.**

4. **"Manage settings" (Sozlamalarni Boshqarish) bosing.**

5. **Pastda "Exclusions" (Istisno) topiladi. "Add or remove exclusions" (Istisno Qo'shish/Olib tashlash) bosing.**

6. **"Add an exclusion" (Istisno Qo'shish) → "Folder" (Papka) tanlang.**

7. **Papka tanlash oynasida o'rnatilgan papkani tanlang:**
   - Default: `C:\AlochiMonitoring`
   - Agar boshqa joyga o'rnatdingiz, o'sha papkani tanlang.

8. **"Select Folder" (Papkani Tanlash) bosing, keyin tasdiqlang.**

**O'zbekcha rasm:**
```
Settings → Privacy & security → Windows Security 
  → Virus & threat protection 
    → Manage settings 
      → Exclusions 
        → Add an exclusion 
          → Folder 
            → C:\AlochiMonitoring
```

---

## 3. Kaspersky Istisno Qo'shish

### Qadam-bo'yama

1. **Kaspersky oilasini aç (sistem qo'ng'iroq yonidagi icon).**

2. **"Settings" (Sozlamalar) bosing.**

3. **"Threats and Exclusions" (Tahdidlar va Istisno) topib tanlang.**

4. **"Manage exclusions" (Istisno Boshqarish) bosing.**

5. **"Add exception" (Istisno Qo'shish) bosing.**

6. **Papka yoki fayl tanlang → `C:\AlochiMonitoring` papkasini bosing.**

7. **"OK" yoki "Apply" (Qo'llash) bosing.**

---

## 4. Avast / AVG Istisno Qo'shish

### Qadam-bo'yama

1. **Avast/AVG ilovasini aç.**

2. **"Menu" (☰) bosing → "Settings" (Sozlamalar) tanlang.**

3. **"General" (Umumiy) bosing.**

4. **"Exceptions" (Istisno) topib tanlang.**

5. **"Add exception" (Istisno Qo'shish) yoki "+" tugmasi bosing.**

6. **Papka tanlang → `C:\AlochiMonitoring` papkasini bosing.**

7. **"OK" yoki "Confirm" (Tasdiqlash) bosing.**

---

## 5. BitDefender Istisno Qo'shish

### Qadam-bo'yama

1. **BitDefender ilovasini aç.**

2. **"Settings" (Sozlamalar) bosing.**

3. **"Exclusions" (Istisno) bo'limini topib tanlang.**

4. **"Add" (Qo'shish) bosing.**

5. **"Browse" (Izlash) bosilgan holda `C:\AlochiMonitoring` papkasini tanlang.**

6. **"Add" yoki "OK" bosing.**

---

## 6. Microsoft Defender (PowerShell orqali — Xodimlar uchun)

Agar GUI orqali qilmasdan PowerShell bilan qilmoqchi bo'lsangiz:

```powershell
# PowerShell-ni Administrator sifatida aç
Add-MpPreference -ExclusionPath "C:\AlochiMonitoring"

# Tasdiqlash:
Get-MpPreference | Select-Object -ExpandProperty ExclusionPath
```

---

## 7. Agar masala davom etsa

1. **Antivirusni butunlay o'chiring yoki "Real-time scanning" (Real-vaqt skanerlash) o'chiring** — vaqtinchalik.
2. **O'rnatishni qayta urinib ko'ring.**
3. **O'rnatgandan keyin antivirusni qayta yoqing.**

---

## 8. Taqdim qilingan Xato (False Positive) Haqida

Agar ogohlantirish yangi o'rnatilmani sababli bo'lsa, antiviruslar kompaniyalaridan dasturni whitelist qilmasini so'ray olasiz. Qarang: [FALSE_POSITIVE.md](./FALSE_POSITIVE.md)

---

**Savol bo'lsa:** @AlochiSupport ga yozing yoki Alochi Monitoring GitHub-dagi issue ochmang.
