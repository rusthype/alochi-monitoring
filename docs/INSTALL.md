# Alochi Monitoring — O'rnatish

## Tavsif

Alochi Monitoring — O'zbekistondagi maktablarda o'quvchilarni test qilish tizimi uchun Windows dasturi. U o'qituvchilar va adminlarni real vaqtda test jarayonini kuzatishga yordam beradi.

---

## O'rnatish usullari

### 1. **Asosiy usul: Setup.exe (tavsiya qilinadi)** ⭐

Bu usul eng oson va xavfsiz.

1. **Setup.exe ni yuklab oling:**
   - https://github.com/rusthype/alochi-monitoring/releases/latest sahifasiga boring
   - `AlochiMonitoring-*.exe` faylni topib, bosing

2. **O'rnatishni boshlang:**
   - Yuklab olingan `.exe` faylni ikki marta bosing
   - Admin huquqi talab qilinsa, **"Ha"** bosing
   - O'rnatish oynasi ochiladi

3. **O'rnatishni yakunlang:**
   - **Next →** bosing va ko'rsatilgan papkani tanlang (asosiy: `C:\Program Files\AlochiMonitoring`)
   - **Install** bosing
   - O'rnatish tugaganidan keyin **Finish** bosing

4. **Dasturni ishga tushiring:**
   - Desktop'da **Alochi Monitoring** yorlig'i paydo bo'ladi
   - Uni bosib, dastur ishga tushadi

### 2. **Portable usul: Zip archivi**

Agar o'rnatish o'rniga to'g'ridan kerakni ishlatmoqchi bo'lsangiz:

1. https://github.com/rusthype/alochi-monitoring/releases/latest dan `alochi-monitoring-windows.zip` ni yuklab oling
2. Zip faylni istalgan papkaga (masalan, `C:\Alochi`) ochib qo'ying
3. `alochi_monitoring.exe` ni ishga tushiring

Protani bu usul bilan boshqaruv qila olasiz, lekin qisqa maqtada o'rnatish tavsiya qilinadi.

---

## SmartScreen xatosi chiqsa

Windows SmartScreen qo'shimcha xabar ko'rsatishi mumkin:

1. **"Qo'shimcha ma'lumot"** tugmasini bosing
2. **"Baribir ishga tushirish"** (Run anyway) ni tanlang

Bu xato yo'q — GitHub dan to'g'ri yuklab olingan fayl xavfsiz.

---

## O'rnatishni o'chirish

1. **Boshlanish** (Start) menu → **Sozlamalar** (Settings) ochib oling
2. **Ilovalar** (Apps) → **O'rnatilgan ilovalar** (Installed apps) bosing
3. **Alochi Monitoring** ni topib, **O'chirish** (Uninstall) bosing
4. Tasdiq oynasi chiqsa, **O'chirish** (Uninstall) ni yana bosing

---

## Yangilash

Alochi Monitoring avtomatik yangilanmaydi. Yangi versiya chiqsa:

1. Eski versiyani o'chiring (yuqorida aytilganidek)
2. Yangi `Setup.exe` ni yuklab oling va o'rnatishni qayta boshlang

---

## Muammolar

### "Access is denied" xatosi
- PowerShell / Command Prompt ni **Administrator sifatida** ishga tushiring

### Dastur ishga tushmaydi
- Windows Defender / antivirus dastur faylini blokirovka qilgan bo'lishi mumkin
- **Sozlamalar** → **Xavfsilik va himoya** (Security) → **Virus va tahdidlardan himoya** → **Himoya sozlamalari** ni ochib, `C:\Program Files\AlochiMonitoring` papkasini whitelist qo'ying

### Boshqa savol
- GitHub issues sahifasida savol bering: https://github.com/rusthype/alochi-monitoring/issues

---

## Ilg'or: PowerShell skripti orqali o'rnatish

Agar PowerShell'da bir qatorlik buyruq orqali o'rnatish istasangiz:

```powershell
iex (irm https://raw.githubusercontent.com/rusthype/alochi-monitoring/main/install.ps1)
```

Bu skript avtomatik ravishda:
- Eng so'nggi versiyani GitHub'dan topadi
- Yuklab oladi
- O'rnatadi
- Desktop yorlig'i yaratadi

**Diqqat:** Bu usul SmartScreen tomonidan ko'proq xabar ko'rsatishi mumkin. Yuqoridagi Setup.exe usuli ta'minot qilingan versiya bo'lgani uchun tavsiya qilinadi.

---

*Oxirgi yangilanish: 2026-yil iyun*
