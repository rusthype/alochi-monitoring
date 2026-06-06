# Xato Detekciyani Hisobot Qilish / Reporting False Positive Detections

Alochi Monitoring o'rnatuvchi dasturi antiviruslar tomonidan "zararli" sifatida aniqlanadi, lekin bu **xato detekciya (false positive)**. Bu faylda qanday qilib antivirus kompaniyalariga hisobot berish kerakligi tushuntiriladi.

---

## Nima uchun xato detekciya sodir bo'ladi?

- **Yangi o'rnatilmagan sertifikat:** Dastur imzosi yangi, sertifikat tanilmagan
- **Qora jadval:** Kompilya qilingan kod avvalroq uchrashmagan bo'lsa, "shubhali" deb hisoblanadi
- **Yuqori takrorlanmasi:** Dastur ko'p yuklab olingandan keyin avtomatik reputatsiya ortadi

---

## 1. Microsoft Defender (Windows) — Hisobot Berish

**URL:** https://www.microsoft.com/en-us/wdsi/filesubmission

### Qadam-bo'yama

1. **Linkni oching.**
2. **"Product" tanlang: "Microsoft Defender"** (yoki shunga o'xshash)
3. **Fayl yuklang: `AlochiMonitoring-<version>-Setup.exe`** (Windows installer)
4. **Hisob berish turi: "Incorrectly detected as malware"** (xato detekciya)
5. **Izoh qo'shing (pastda berilgan matn ni copy qiling):**

```
Alochi Monitoring is a legitimate Flutter desktop application used by 
schools in Uzbekistan for offline test administration and student 
assessments. The application is open-source and publicly available at 
https://github.com/rusthype/alochi-monitoring.

The application is built with Flutter (Google's framework) and distributed 
as a signed Windows installer. The detection is a false positive due to 
the application being newly signed and not yet built up reputation with 
security vendors.

Company: Alochi Education Platform
Contact: https://github.com/rusthype/alochi-monitoring
License: Open Source (see repo)
```

6. **Taqqoslash uchun SHA256 ni topish:**
   ```powershell
   Get-FileHash "C:\path\AlochiMonitoring-Setup.exe" -Algorithm SHA256
   ```
   Bu hash-ni hisobot-da qo'shing (opsional).

7. **Submit (Yuborish) bosing.**

---

## 2. Kaspersky — Hisobot Berish

**URL-lar:**
- Analiz: https://opentip.kaspersky.com
- Xato detekciya formasi: https://support.kaspersky.com/false-detection

### Qadam-bo'yama

1. **https://opentip.kaspersky.com ochib, fayl yuklang.**
2. **Kaspersky analiz qiladi, natija beradi.**
3. **Agar "malware" desa, "Report false detection" (xato detekciya) tugmasini bosing.**
4. Yoki **https://support.kaspersky.com/false-detection dan to'g'ridan-to'g'ri hisobot bering:**
   - File: `AlochiMonitoring-<version>-Setup.exe`
   - Detection name: (Kaspersky uning nomini ko'rsatgan bo'lsa, copy qiling)
   - Reason: "Legitimate Flutter application for educational use"
   - Izoh: (yuqoridagi matnni qo'shing)

5. **Submit.**

---

## 3. Avast / AVG — Hisobot Berish

**URL:** https://www.avast.com/false-positive-file-form.php

### Qadam-bo'yama

1. **Linkni oching.**
2. **"Submit file for analysis" (Fayl tahlilga yuborish) yoki "Report false positive" (xato detekciya) tanlang.**
3. **Fayl yuklang: `AlochiMonitoring-<version>-Setup.exe`**
4. **Kontakt ma'lumotlari:**
   - Email: iamfakhriddin@gmail.com (yoki @AlochiSupport)
   - Company: Alochi Education Platform
5. **Izoh:**
   ```
   Legitimate Flutter educational application. Open-source at 
   github.com/rusthype/alochi-monitoring. False positive due to 
   new/unsigned distribution.
   ```
6. **Submit.**

---

## 4. McAfee / Norton — Hisobot Berish

**URL:** https://www.mcafee.com/en-us/support/contact.html (Support)

Yoki to'g'ridan-to'g'ri:
- McAfee: https://www.mcafee.com/en-us/anti-virus/how-to-clean-an-infected-pc.html (support page)
- Norton: https://support.norton.com/sp/en/us/home/current/solutions/v93230263_EndUserProfile_en_us (submit)

---

## 5. Windows Defender (Azure Threat Intelligence)

Agar Windows Defender xabar bersdan keyin hisobot berish:

1. **"View details" (Tafsilotlar) bosing → "Feedback" (Fikr) yoki "Report" (Hisobot) bosing.**
2. **"This should not have been detected" (Bu aniqlanmasligi edi) tanlang.**
3. **Submit.**

---

## 6. Bitdefender / Trend Micro / Others

Umumiy yo'l:
- **Kompaniya saytiga kirish → "Threat Submission" (Tahdid Hisoboti) yoki "False Positive" (Xato Detekciya) bo'limi topish**
- **Fayl va izoh yuborish**

---

## 7. Reputatsiya Qayta Tiklash — Timeline

Hisobotdan keyin:

| Vaqt | Sodir bo'lgan | Izoh |
|------|---------------|------|
| **Darhol** | Hisobot qabul qilinadi | Xabar: "Review in progress" |
| **1-3 kun** | Tekshiruv | Kompaniya tahlil qiladi |
| **3-7 kun** | Whitelist | Agar o'z yo'ligidagi bo'lsa, qo'shadi |
| **1 hafta** | Reputatsiya | Yuklashlar ko'payti, avtomatik reputatsiya ortadi |

> **Muhim:** Har yangi **build** (versiya) yangi hash ga ega → Yangi hisobotlar kerak bo'ladi!

---

## 8. GitHub Release-dagi SHA256

GitHub release page-da fayl hash-ini topish:

1. **https://github.com/rusthype/alochi-monitoring/releases ga oching**
2. **"Assets" (Aktivlar) bo'limida `AlochiMonitoring-Setup.exe` ni topib, size yoniga hash ko'ring**
3. Yoki **Release description-da hash berilgan bo'lishi mumkin**

PowerShell-da local checksum:
```powershell
Get-FileHash "C:\Users\<user>\Downloads\AlochiMonitoring-Setup.exe" -Algorithm SHA256
```

---

## 9. Future: Code Signing (Imzolash)

Agar project **SignPath Foundation** dan **FREE OV sertifikat** olsa, imzolanmagan (`$null`) dasturni imzolanganiga aylantiriladi → False positive yo'qoladi.

Qarang: [SIGNPATH_OSS.md](./SIGNPATH_OSS.md)

---

## 10. User-larga nima aytish kerak?

Agar foydalanuvchi ("O'qituvchi") xata detekciya haqida so'rasа:

> Alochi Monitoring — to'liq zararsiz open-source dastur. Antivirusning ogohlantirishi - yangi o'rnatilganlik sababli. Qarang: [ANTIVIRUS_YECHIM.md](./ANTIVIRUS_YECHIM.md)
>
> Dasturni o'rnatmoqchi bo'lsangiz, SmartScreen "Run anyway" tanlang yoki Defender-ga istisno qo'shing.

---

**Tirik tavsiya:** Har yangi release-dan keyin Microsoft Defender-ga hisobot bering (qo'lda 2-3 minut ishlaydi) — bu eng muhim vendor.

**Support:** GitHub Issues yoki @AlochiSupport
