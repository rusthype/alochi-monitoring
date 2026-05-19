; Alochi Monitoring — Inno Setup Script
; - Program Files ga o'rnatadi
; - AppData da foydalanuvchi ma'lumotlari (saqlanadi update/uninstall da)
; - Update: eski versiya ustiga o'rnatiladi, ma'lumotlar saqlanadi
; - Uninstall: Program Files tozalanadi, AppData SAQLANADI (o'quvchi natijalari)

#define AppName      "Alochi Monitoring"
#define AppVersion   "1.0.6"
#define AppPublisher "Alochi Education"
#define AppURL       "https://alochi.org"
#define AppExeName   "alochi_monitoring.exe"
#define AppGUID      "{{A1OCH1-ALOCHI-MON1T-2026-EDUCATION}}"

[Setup]
AppId={#AppGUID}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
AppUpdatesURL=https://github.com/rusthype/alochi-monitoring/releases/latest

; O'rnatish joyi
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes

; Chiqish fayl nomi
OutputBaseFilename=AlochiMonitoring-{#AppVersion}-Setup

; Kompressiya
Compression=lzma2/ultra64
SolidCompression=yes

; UI
WizardStyle=modern
SetupIconFile=windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
UninstallDisplayName={#AppName}

; Ruxsatlar
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible

; Muhim: Update paytida ilovani yopadi
CloseApplications=yes
CloseApplicationsFilter=*alochi_monitoring.exe*
RestartApplications=no

; Version info
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName}
VersionInfoProductName={#AppName}

[Languages]
Name: "uzbek"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Desktop shortcut"; GroupDescription: "Qo'shimcha:"; Flags: unchecked

[Files]
; Program Files ga faqat bajariladigan fayllar
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; \
  Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}";   Filename: "{app}\{#AppExeName}"
Name: "{group}\O'chirish";    Filename: "{uninstallexe}"
Name: "{commondesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"; \
  Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; \
  Description: "{cm:LaunchProgram,{#AppName}}"; \
  Flags: nowait postinstall skipifsilent

[UninstallDelete]
; Program Files papkasini to'liq tozalash
Type: filesandordirs; Name: "{app}"
; AppData da foydalanuvchi ma'lumotlari SAQLANADI
; {userappdata}\alochi_monitoring — o'chirilmaydi (qasddan)

[Code]
// Yangi o'rnatish yoki update ekanligini aniqlash
function IsUpgrade(): Boolean;
var
  PrevVersion: String;
begin
  Result := RegQueryStringValue(HKLM,
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{#AppGUID}_is1',
    'DisplayVersion', PrevVersion);
end;

procedure InitializeWizard;
begin
  if IsUpgrade() then begin
    WizardForm.WelcomeLabel2.Caption :=
      'Alochi Monitoring yangi versiyasi o''rnatilmoqda.' + #13#10 +
      'Sizning ma''lumotlaringiz saqlanib qoladi.';
  end;
end;
