# Alochi Monitoring — Windows O'rnatish
# PowerShell (Admin) da ishga tushiring:
#   iex (irm https://raw.githubusercontent.com/rusthype/alochi-monitoring/main/install.ps1)

$ErrorActionPreference = "Stop"
$Repo       = "rusthype/alochi-monitoring"
$InstallDir = "C:\AlochiMonitoring"
$AppName    = "Alochi Monitoring"

Write-Host ""
Write-Host "  ╔═══════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     Alochi Monitoring         ║" -ForegroundColor Cyan
Write-Host "  ║   Maktab test tizimi          ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Admin tekshiruv
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  [!] Admin PowerShell kerak!" -ForegroundColor Red
    Write-Host "  PowerShell ni 'Administrator sifatida ishga tushirish' orqali oching."
    pause; exit 1
}

# Eng so'nggi versiyani GitHub'dan topish
Write-Host "  [1/4] Versiya tekshirilmoqda..." -ForegroundColor Yellow
$ApiUrl = "https://api.github.com/repos/$Repo/releases/latest"
try {
    $Release = Invoke-RestMethod -Uri $ApiUrl -Headers @{Accept="application/vnd.github.v3+json"} -UseBasicParsing
    $Asset = $Release.assets | Where-Object { $_.name -like "*latest*" -or $_.name -like "*windows*" } | Select-Object -First 1
    if (-not $Asset) { $Asset = $Release.assets | Select-Object -First 1 }
    $DownloadUrl = $Asset.browser_download_url
    $Version = $Release.tag_name
} catch {
    # Fallback: to'g'ridan release URL
    $DownloadUrl = "https://github.com/$Repo/releases/latest/download/alochi-monitoring-windows.zip"
    $Version = "latest"
}

Write-Host "  Versiya: $Version" -ForegroundColor Gray

# Yuklab olish
Write-Host "  [2/4] Yuklab olinmoqda..." -ForegroundColor Yellow
$ZipPath = Join-Path $env:TEMP "alochi-monitoring.zip"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing
$SizeMB = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
Write-Host "  OK: $SizeMB MB yuklandi" -ForegroundColor Green

# O'rnatish
Write-Host "  [3/4] O'rnatilmoqda: $InstallDir ..." -ForegroundColor Yellow
if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
New-Item -ItemType Directory -Path $InstallDir | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $InstallDir)
Remove-Item $ZipPath -Force

# EXE topish
$ExePath = Get-ChildItem -Path $InstallDir -Filter "*.exe" -Recurse |
           Where-Object { $_.Name -notlike "*.dll" } |
           Sort-Object Length -Descending |
           Select-Object -First 1 -ExpandProperty FullName

if (-not $ExePath) {
    Write-Host "  [!] Xato: .exe topilmadi!" -ForegroundColor Red
    exit 1
}

# Desktop yorliq
Write-Host "  [4/4] Desktop yorlig'i yaratilmoqda..." -ForegroundColor Yellow
$WshShell = New-Object -comObject WScript.Shell
$LnkPath  = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "$AppName.lnk"
$Shortcut = $WshShell.CreateShortcut($LnkPath)
$Shortcut.TargetPath      = $ExePath
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.IconLocation    = $ExePath
$Shortcut.Description     = $AppName
$Shortcut.Save()

# Natija
Write-Host ""
Write-Host "  ✓ O'rnatish muvaffaqiyatli yakunlandi!" -ForegroundColor Green
Write-Host ""
Write-Host "  Dastur: $ExePath" -ForegroundColor Cyan
Write-Host "  Desktop: $AppName" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Ishga tushirish uchun Desktop'dagi '$AppName' yorlig'ini bosing."
Write-Host ""
