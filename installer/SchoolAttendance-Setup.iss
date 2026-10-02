; School Attendance Portal — unified Windows installer (Inno Setup 6)
; Bundles Flutter app + K50 Bridge. Start Menu + Windows Search + Desktop Icon + Scheduled Task.
;
; Build: .\installer\build-installer.ps1
; Requires Inno Setup 6: https://jrsoftware.org/isdl.php

#define MyAppName "School Attendance Portal"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "School System Solutions"
#define MyAppURL "https://github.com/getneuralnest/SAS"
#define MyAppExeName "school_attendance_portal.exe"

#ifexist "..\build\windows\x64\runner\Release\school_attendance_portal.exe"
#else
  #error "Build Flutter Windows first: scripts\build-client-delivery.ps1"
#endif

#ifexist "..\k50-bridge\dist\K50Bridge-Client\K50Bridge.exe"
#else
  #error "Build K50 Bridge first: k50-bridge\build-client-package.ps1"
#endif

[Setup]
AppId={{C1D2E3F4-A5B6-7890-EF01-SCHOOLATTENDANCE}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
DefaultDirName={autopf}\School Attendance Portal
DefaultGroupName={#MyAppName}
DisableProgramGroupPage=yes
LicenseFile=
OutputDir=..\dist\client
OutputBaseFilename=SchoolAttendance-Setup
Compression=lzma2/ultra64
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=admin
ArchitecturesInstallIn64BitMode=x64compatible
SetupIconFile=app_icon.ico
CloseApplications=no
SetupLogging=yes
RestartApplications=no
UninstallDisplayIcon={app}\App\{#MyAppExeName}
MinVersion=10.0

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Additional icons:"; Flags: checkedonce
Name: "autostart"; Description: "Start app and K50 Bridge when Windows starts"; GroupDescription: "Startup:"; Flags: checkedonce

[Files]
; Flutter Windows app (entire Release folder)
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}\App"; Flags: ignoreversion recursesubdirs createallsubdirs
; K50 Bridge (published client folder)
Source: "..\k50-bridge\dist\K50Bridge-Client\*"; DestDir: "{app}\K50Bridge"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "Install.exe"
; Post-install and helper scripts
Source: "pre-install.ps1"; Flags: dontcopy
Source: "school-process-control.ps1"; Flags: dontcopy
Source: "post-install.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "school-process-control.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "repair-k50-com.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "register-k50-bridge-task.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "start-k50-bridge.vbs"; DestDir: "{app}\K50Bridge"; Flags: ignoreversion
Source: "start-k50-bridge.cmd"; DestDir: "{app}\K50Bridge"; Flags: ignoreversion
Source: "start-all-k50-bridges.cmd"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\App\{#MyAppExeName}"; WorkingDir: "{app}\App"; Comment: "School Attendance Portal"
Name: "{group}\K50 Bridge Settings"; Filename: "notepad.exe"; Parameters: """{app}\K50Bridge\appsettings.json"""; Comment: "K50 Scanner IP (port 8787)"
Name: "{group}\View K50 Bridge Logs"; Filename: "notepad.exe"; Parameters: """{commonappdata}\School Attendance Portal\K50Bridge\logs\k50_bridge.log"""; Comment: "View K50 hardware bridge logs"
Name: "{group}\K50 Bridge Settings"; Filename: "notepad.exe"; Parameters: """{commonappdata}\School Attendance Portal\K50Bridge\k50_config.json"""; Comment: "K50 Scanner IP & Port (port 8787)"
Name: "{group}\Repair K50 Fingerprint"; Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\repair-k50-com.ps1"" -InstallDir ""{app}"""; Comment: "Fix fingerprint COM registration"; WorkingDir: "{app}\installer"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\App\{#MyAppExeName}"; WorkingDir: "{app}\App"; Tasks: desktopicon
Name: "{commonstartup}\{#MyAppName}"; Filename: "{app}\App\{#MyAppExeName}"; WorkingDir: "{app}\App"; Tasks: autostart
Name: "{commonstartup}\School Attendance K50 Bridge"; Filename: "{app}\start-all-k50-bridges.cmd"; WorkingDir: "{app}"; Tasks: autostart

[Registry]
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; ValueType: string; ValueName: ""; ValueData: "{app}\App\{#MyAppExeName}"; Flags: uninsdeletekey
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\App Paths\{#MyAppExeName}"; ValueType: string; ValueName: "Path"; ValueData: "{app}\App"; Flags: uninsdeletekey

[Run]
Filename: "powershell.exe"; Parameters: "-NoProfile -ExecutionPolicy Bypass -File ""{app}\installer\post-install.ps1"" -InstallDir ""{app}"""; StatusMsg: "Registering K50 SDK and starting background services..."; Flags: runhidden waituntilterminated
Filename: "{app}\App\{#MyAppExeName}"; Description: "Launch {#MyAppName}"; Flags: nowait postinstall skipifsilent; WorkingDir: "{app}\App"

[UninstallRun]
Filename: "schtasks.exe"; Parameters: "/Delete /TN ""SchoolAttendance-K50Bridge"" /F"; RunOnceId: "RemoveBridgeTask"; Flags: runhidden skipifdoesntexist
Filename: "schtasks.exe"; Parameters: "/Delete /TN ""SchoolAttendance-App"" /F"; RunOnceId: "RemoveAppTask"; Flags: runhidden skipifdoesntexist

[Code]
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  ResultCode: Integer;
begin
  { Stop school app and bridges before copying new files }
  ExtractTemporaryFile('pre-install.ps1');
  ExtractTemporaryFile('school-process-control.ps1');
  if Exec('powershell.exe',
    ExpandConstant('-NoProfile -ExecutionPolicy Bypass -File "{tmp}\pre-install.ps1"'),
    '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Log('pre-install exit code: ' + IntToStr(ResultCode))
  else
    Log('pre-install failed to start');
  Result := '';
end;
