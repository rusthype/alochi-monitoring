# Код Имзолаш (Code Signing) — Alochi Monitoring

Bu qo'llanmada Windows .exe fayllarini Authenticode imzosi bilan to'rtlash jarayoni tasvirlanadi.

## 1. Sertifikat Yaratish (Self-Signed)

Admin PowerShell-da:
```powershell
New-SelfSignedCertificate -Type CodeSigningCert -Subject "CN=Alochi" `
  -CertStoreLocation Cert:\CurrentUser\My -KeyUsage DigitalSignature `
  -KeyExportPolicy Exportable -NotAfter (Get-Date).AddYears(5)
```

Chiqarish: Sertifikat ID raqami (thumbprint) ko'rinadi.

## 2. PFX va CER Eksporti

**PFX eksporti** (parol bilan):
```powershell
$cert = Get-ChildItem Cert:\CurrentUser\My | Where-Object { $_.Subject -eq "CN=Alochi" }
$pwd = ConvertTo-SecureString -String "YourPasswordHere" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "alochi.pfx" -Password $pwd
```

**CER eksporti** (public):
```powershell
Export-Certificate -Cert $cert -FilePath "alochi.cer" -Type CERT
```

## 3. PFX ni Base64 ga Kodlash

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("alochi.pfx")) | Set-Content alochi-pfx-base64.txt
```

Fayl: `alochi-pfx-base64.txt` — GitHub sekreti uchun.

## 4. GitHub Sekreti Qo'shish

GitHub repo Settings:
- **Secrets and variables** → **Actions**
- **New repository secret:**
  - `SIGNING_PFX_BASE64` = Yuqorida hosil bo'lgan base64 matn
  - `SIGNING_PFX_PASSWORD` = PFX parol

## 5. Sertifikatni Komputerlarga O'rnatish

Har bir maktab komputeriga public sertifikatni qo'shish (imzolangan fayllarni ishonish uchun):

### GUI (certlm.msc)
1. `Win + R` → `certlm.msc` → Enter
2. **Trusted Root Certification Authorities** → **Certificates**
3. O'ng klik → **All Tasks** → **Import...**
4. `alochi.cer` tanlang → **Next** → **Place all certificates in the following store: Trusted Root Certification Authorities** → **Finish**

### PowerShell (Admin)
```powershell
Import-Certificate -FilePath "alochi.cer" -CertStoreLocation Cert:\LocalMachine\Root
Import-Certificate -FilePath "alochi.cer" -CertStoreLocation Cert:\LocalMachine\TrustedPublisher
```

### Guruh Siyosati (Domain)
Barcha PC larni avtomatik qilish uchun Group Policy:
```
gpedit.msc → Computer Configuration → Windows Settings → Security Settings →
Public Key Policies → Trusted Root Certification Authorities
```
`alochi.cer` ni Group Policy o'rnatish.

## 6. SmartScreen Ogohlantirishi Bartaraf Etish

**Self-signed sertifikat bilan:**
- Sertifikat **Trusted Root** da bo'lsa, **SmartScreen warn** yo'q
- Domain guruh orqali o'rnatilgan katta flot uchun ishlaydi
- Alohida PC lar uchun har bir OP dan tasdiq kerak

**Universal (hemdobarcha siz) uchun:**
- SignPath OSS ishlatish (free, community organizations uchun)
- OV/EV sertifikat sotib olish (Microsoft, DigiCert)

## 7. Verificatsiya

Imzolangan .exe:
```powershell
Get-AuthenticodeSignature "AlochiMonitoring-1.0.0-Setup.exe"
```

Chiqish: `Status: Valid` ← imzo tugri.

---

**Kattalar uchun eslatma:** Self-signed faqat ishonch sertifikatini o'rnatadiganlarni xavfsiz qiladi.
Hemdobarbarcha foydalanuvchilar uchun SmartScreen ogohlantirishi bartaraf etish uchun SignPath OSS yoki OV/EV sertifikat kerak.
