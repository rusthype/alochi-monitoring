# SignPath Foundation — Bepul Code Signing for Open Source / Öзбек

> **Мақсад:** Alochi Monitoring uchun **bepul OV (Organization Validation) code-signing sertifikat** olish jarayoni

---

## 1. SignPath Foundation Nima?

**SignPath** — Microsoft Authenticode code-signing sertifikatlarni bepul ta'minlaydigan fondatsiya.

- **Muddati:** 1 yil (yangi sertifikat)
- **Qiymati:** $200-400 (bepul!)
- **Tuslash:** GitHub Actions CI/CD ga birlashtirish

**URL:** https://about.signpath.io/product/open-source

---

## 2. Talablar — Qo'shiladigan Narsalar

Alochi Monitoring **kerakli bo'lgan talablarning ko'pini** bajargan:

| Talabi | Status | Eslatma |
|--------|--------|---------|
| Public GitHub repo | ✅ Bajarilgan | rusthype/alochi-monitoring |
| Open-source LICENSE | ❌ **ETIBOR!** | **Repo-da LICENSE fayli yo'q — QO'SHISH KERAK** |
| Project description | ✅ Bajarilgan | README.md + CLAUDE.md |
| Active maintainer | ✅ Bajarilgan | GitHub account (rusthype) |

### ⚠️ KRITIK: LICENSE Fayli Qo'shish Kerak

**Hozirgi holat:** Repo-da LICENSE fayli **yo'q**. SignPath-ga qabul qilindirish uchun qo'shilishi kerak.

**Tafsiya etilgan litsenziya:** `MIT` yoki `Apache-2.0`

#### MIT License Qo'shish (eng sodda):

1. **Repo root-ga `LICENSE` fayli yaratish:**
   ```
   MIT License

   Copyright (c) 2024 Alochi Education Platform (rusthype)

   Permission is hereby granted, free of charge, to any person obtaining a copy
   of this software and associated documentation files (the "Software"), to deal
   in the Software without restriction, including without limitation the rights
   to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
   copies of the Software, and to permit persons to whom the Software is
   furnished to do so, subject to the following conditions:

   The above copyright notice and this permission notice shall be included in all
   copies or substantial portions of the Software.

   THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
   IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
   FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
   AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
   LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
   OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
   SOFTWARE.
   ```

2. **Commit + push:**
   ```bash
   git add LICENSE
   git commit -m "chore: add MIT license"
   git push origin main
   ```

---

## 3. SignPath Foundation Ariza Berish — Qadam-bo'yama

### 3.1 Ro'yxatdan O'tish

1. **https://signpath.org ga oching**
2. **"Sign up for free" (Bepul ro'yxatdan o'tish) yoki "Developer" tanlang**
3. **GitHub account bilan kirish yoki email bilan ro'yxat qiling**
   - Email: iamfakhriddin@gmail.com
   - Password: (kuchli parol)
4. **Email ni tasdiqlang**

### 3.2 Organization Yaratish

1. **SignPath dashboard-da "Create Organization" (Tashkilot Yaratish) bosing**
2. **Name:** `Alochi Education`
3. **Website:** `https://github.com/rusthype/alochi-monitoring`
4. **Description:** 
   ```
   Alochi Monitoring is a Flutter desktop application for offline 
   educational testing in schools across Uzbekistan. 
   Open-source under MIT License.
   ```
5. **Create.**

### 3.3 OSS (Open Source) Dastur Uchun Ariza Berish

1. **"Apply for free code-signing" (Bepul code-signing uchun ariza) bosing**
2. **"Open Source Project" (Ochiq Manba Loyihasi) tanlang**
3. **Quyidagini to'ldiring:**

   | Maydon | Ma'lumot |
   |-------|---------|
   | Project name | Alochi Monitoring |
   | Project URL | https://github.com/rusthype/alochi-monitoring |
   | License | MIT (yoki Apache-2.0) |
   | Build system | GitHub Actions (ci) |
   | Maintainer email | iamfakhriddin@gmail.com |
   | Maintainer GitHub | rusthype |

4. **Submit Application (Ariza Yuborish)**

### 3.4 Tekshiruv Davri (1-2 hafta)

SignPath jamoasi:
- Repo public ekanligini tekshiradi ✅
- LICENSE fayli bor ekanligini tekshiradi (agar yo'q bo'lsa, rad etadi)
- Build-pipeline tekshiradi
- Approval yoki additional questions jo'natadi

---

## 4. GitHub Actions-ga SignPath Integratsiyasi (Keyin)

Agar SignPath approval bersa, build-windows.yml-ga qo'shiladi:

### 4.1 Hozirgi Holat (Self-signed)

```yaml
# build-windows.yml ichida
- name: Sign executable
  run: |
    signtool sign /f certificate.pfx /p "${{ secrets.CERT_PASSWORD }}" ...
```

### 4.2 SignPath Bilan

```yaml
- name: Sign with SignPath
  uses: signpath/github-action@v0
  with:
    api-token: ${{ secrets.SIGNPATH_API_TOKEN }}
    signing-request-description: 'Alochi Monitoring v${{ env.VERSION }}'
    artifact-configuration-name: 'AlochiMonitoring'
    input-artifact-path: 'build/windows/x64/runner/Release/alochi_monitoring.exe'
    output-artifact-path: 'build/windows/x64/runner/Release/AlochiMonitoring-Setup.exe'
```

**Keyin:**
- SignPath `SIGNPATH_API_TOKEN` secret-ini beradi
- GitHub Actions avtomatik imzolaydi
- Release-ga imzolangan binary qo'shiladi

---

## 5. Timeline va Ish Tartibi

### 5.1 Hozir (bugun)
- ✅ LICENSE fayli qo'shish (MIT)
- ✅ Commit + push
- ⏳ SignPath ariza berish

### 5.2 Keying 1-2 hafta
- SignPath tekshiruv
- Approval (kutilmoqda)

### 5.3 Keying 3-4 hafta
- SignPath sertifikat olinadi
- GitHub Actions + CI test (opt-in)
- Sertifikat sekret-ga qo'shiladi
- Yangi build-dan keyin avtomatik imzolash boshlaydi

### 5.4 Uzun muddatda
- **False positive yo'qoladi** — imzolangan binary
- **Reputatsiya ortadi** — antivirus vendors taniydi
- **User install eda xeta xabar yo'q** — bu ideal!

---

## 6. Vaqtinchalik Yechim (SignPath kutilyotganda)

**Bu vaqtda:**
1. Self-signed `.pfx` sertifikat bilan Build qilish (hozirgi holat)
2. Release-ga SHA256 hash qo'shish
3. Microsoft Defender + Kaspersky-ga xato detekciya hisoboti berish
   - Qarang: [FALSE_POSITIVE.md](./FALSE_POSITIVE.md)
4. [ANTIVIRUS_YECHIM.md](./ANTIVIRUS_YECHIM.md)-da istisno qo'shish yo'riqnomasi

**Ikki hafta ichida:** Avtomatik reputatsiya ortadi, false positive kamayadi.

---

## 7. SignPath URLs va Havolalar

| Vosita | URL | Izoh |
|--------|-----|------|
| SignPath Asosiy | https://signpath.org | Ro'yxatdan o'tish |
| OSS Dasturlar | https://about.signpath.io/product/open-source | Qoidalar |
| Dashboard | https://app.signpath.io | Login keyin |
| API Docs | https://docs.signpath.io | CI/CD integration |
| GitHub Action | https://github.com/signpath/github-action | Source |

---

## 8. Muhim Esinlatma: LICENSE Majburi

**Keskinlik:** SignPath Foundation OSS dasturlar uchun:
- **LICENSE fayli TO'LIQ MAJBURI** (MIT, Apache-2.0, GPL, boshqalar)
- Agar yo'q bo'lsa, ariza rad etiladi
- Commit qiling: `git add LICENSE && git commit -m "chore: add MIT license"`

---

## 9. Qo'shimcha: EV Certificate (Kelajakda)

Agar project-ga ko'proq pul bo'lsa:
- **EV (Extended Validation) sertifikat** — $200-400/yil (SignPath-dan tashqari)
- **Imzo kuchli** → SmartScreen ogohlantirishi tuzi chiqmaydi
- **Hozir keraksiz** — MIT free sertifikat yetarli

---

## 10. Qo'llaniladigan Jumboqlar

**Q: SignPath-ga ariza berilgandan keyin necha vaqt chekish kerak?**
A: 1-2 hafta (ba'zida 3-4 kun).

**Q: Agar rad etisadi?**
A: Sababni jo'natadi (masalan "LICENSE yo'q"), tuzatasiz, qayta ariza bering.

**Q: Self-signed sertifikat bilan ishlay olasizmi?**
A: Ha, lekin false positive hisobotlar kerak bo'ladi (qarang FALSE_POSITIVE.md).

**Q: Har yangi build-dan keyin imzolash kerakmi?**
A: Ha! SignPath CI/CD bilan avtomatik qiladi.

---

## 11. CHECKLIST

Alochi Monitoring SignPath uchun tayyor qilish:

- [ ] Repo public: https://github.com/rusthype/alochi-monitoring ✅
- [ ] LICENSE fayli qo'shildi: LICENSE (MIT yoki Apache-2.0) — **QO'SHISH KERAK**
- [ ] README.md bor: ✅ (sodda bo'lsa ham)
- [ ] Maintainer email: iamfakhriddin@gmail.com ✅
- [ ] GitHub Actions: build-windows.yml bor ✅
- [ ] SignPath Foundation ro'yxati: (keyin)
- [ ] OSS dastur uchun ariza: (keyin)
- [ ] Approval kutish: (1-2 hafta)
- [ ] SIGNPATH_API_TOKEN secret qo'shish: (approval keyin)
- [ ] build-windows.yml-ga signpath/github-action qo'shish: (keyin)

---

**Endi qilishi kerak:** 
1. LICENSE qo'shish
2. Commit + push
3. SignPath ariza berish (1-2 kun ichida)

**Support:** GitHub Issues yoki @AlochiSupport
