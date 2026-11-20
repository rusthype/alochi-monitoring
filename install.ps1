# Alochi Monitoring - Windows install script
# NOTE: the preferred method is the signed Setup.exe from the GitHub releases page.
#
# Run in an elevated PowerShell (Administrator):
#   iex (irm https://raw.githubusercontent.com/rusthype/alochi-monitoring/main/install.ps1)
#
# See docs/INSTALL.md for details.

$ErrorActionPreference = "Stop"
$Repo       = "rusthype/alochi-monitoring"
$InstallDir = "C:\AlochiMonitoring"
$AppName    = "Alochi Monitoring"

Write-Host ""
Write-Host "  ╔═══════════════════════════════╗" -ForegroundColor Cyan
Write-Host "  ║     Alochi Monitoring         ║" -ForegroundColor Cyan
Write-Host "  ║   School testing system       ║" -ForegroundColor Cyan
Write-Host "  ╚═══════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Admin check
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  [!] An elevated (Administrator) PowerShell is required!" -ForegroundColor Red
    Write-Host "  Open PowerShell via 'Run as administrator'."
    pause; exit 1
}

# Find the latest build on GitHub
Write-Host "  [1/4] Checking version..." -ForegroundColor Yellow
$ApiUrl = "https://api.github.com/repos/$Repo/releases/tags/latest"
$ZipName = "alochi-monitoring-windows.zip"
$ExpectedHash = $null
try {
    $Release = Invoke-RestMethod -Uri $ApiUrl -Headers @{Accept="application/vnd.github.v3+json"} -UseBasicParsing
    $Asset = $Release.assets | Where-Object { $_.name -eq $ZipName } | Select-Object -First 1
    if (-not $Asset) { throw "asset $ZipName not found in release" }
    $DownloadUrl = $Asset.browser_download_url
    $Version = $Release.tag_name
    # GitHub publishes a "digest": "sha256:<hex>" for every release asset.
    if ($Asset.digest -match '^sha256:([A-Fa-f0-9]{64})$') {
        $ExpectedHash = $Matches[1].ToUpper()
    }
} catch {
    # Fallback: direct tag-based release URL (NOT /latest/download/ - that also
    # skips prereleases, just like /releases/latest). No digest in this path.
    $DownloadUrl = "https://github.com/$Repo/releases/download/latest/$ZipName"
    $Version = "latest"
}

Write-Host "  Version: $Version" -ForegroundColor Gray

# Download
Write-Host "  [2/4] Downloading..." -ForegroundColor Yellow
$ZipPath = Join-Path $env:TEMP "alochi-monitoring.zip"
Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing
$SizeMB = [math]::Round((Get-Item $ZipPath).Length / 1MB, 1)
Write-Host "  OK: downloaded $SizeMB MB" -ForegroundColor Green

# SHA256 check against the digest published by GitHub for the asset
if ($ExpectedHash) {
    $ActualHash = (Get-FileHash $ZipPath -Algorithm SHA256).Hash
    if ($ActualHash -ne $ExpectedHash) {
        Write-Host "  [!] ERROR: SHA256 mismatch! The file is corrupt or has been tampered with." -ForegroundColor Red
        Write-Host "      Expected: $ExpectedHash"
        Write-Host "      Actual:   $ActualHash"
        Remove-Item $ZipPath -Force -ErrorAction SilentlyContinue
        exit 1
    }
    Write-Host "  OK: SHA256 verified" -ForegroundColor Green
} else {
    Write-Host "  [!] Warning: no SHA256 digest found, integrity check skipped" -ForegroundColor Yellow
}

# Install
Write-Host "  [3/4] Installing to $InstallDir ..." -ForegroundColor Yellow
if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force }
New-Item -ItemType Directory -Path $InstallDir | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::ExtractToDirectory($ZipPath, $InstallDir)
Remove-Item $ZipPath -Force

# Locate the EXE
$ExePath = Get-ChildItem -Path $InstallDir -Filter "*.exe" -Recurse |
           Where-Object { $_.Name -notlike "*.dll" } |
           Sort-Object Length -Descending |
           Select-Object -First 1 -ExpandProperty FullName

if (-not $ExePath) {
    Write-Host "  [!] Error: no .exe found!" -ForegroundColor Red
    exit 1
}

# Desktop shortcut
Write-Host "  [4/4] Creating desktop shortcut..." -ForegroundColor Yellow
$WshShell = New-Object -comObject WScript.Shell
$LnkPath  = Join-Path ([Environment]::GetFolderPath("CommonDesktopDirectory")) "$AppName.lnk"
$Shortcut = $WshShell.CreateShortcut($LnkPath)
$Shortcut.TargetPath      = $ExePath
$Shortcut.WorkingDirectory = $InstallDir
$Shortcut.IconLocation    = $ExePath
$Shortcut.Description     = $AppName
$Shortcut.Save()

# Result
Write-Host ""
Write-Host "  ✓ Installation completed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "  App: $ExePath" -ForegroundColor Cyan
Write-Host "  Desktop: $AppName" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Double-click the '$AppName' shortcut on the Desktop to start."
Write-Host ""
