; Journal for Windows — one installer for x64 and ARM64 PCs.
; Per-user install (no admin prompt) into %LOCALAPPDATA%\Programs\Journal, Start menu entry, uninstaller.
;
; Build (from windows\, after publishing both architectures — see build-installer.ps1):
;   ISCC.exe /DAppVersion=0.1.0 /DSrcX64=..\out\Journal-win-x64 /DSrcArm64=..\out\Journal-win-arm64 installer\Journal.iss

#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
#ifndef SrcX64
  #define SrcX64 "..\out\Journal-win-x64"
#endif
#ifndef SrcArm64
  #define SrcArm64 "..\out\Journal-win-arm64"
#endif
#ifndef OutDir
  #define OutDir "..\out"
#endif

[Setup]
AppId={{6E2B3F4A-8C1D-4E5B-9A7F-2D3C4B5A6E7F}
AppName=Journal
AppVersion={#AppVersion}
AppVerName=Journal {#AppVersion}
AppPublisher=daily-journal
AppPublisherURL=https://github.com/pylenius/daily-journal
AppSupportURL=https://github.com/pylenius/daily-journal
DefaultDirName={localappdata}\Programs\Journal
DisableDirPage=yes
DisableProgramGroupPage=yes
DefaultGroupName=Journal
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputDir={#OutDir}
OutputBaseFilename=Journal-Setup-{#AppVersion}
SetupIconFile=..\src\Journal.App\Assets\Journal.ico
UninstallDisplayIcon={app}\Journal.exe
UninstallDisplayName=Journal
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"
Name: "finnish"; MessagesFile: "compiler:Languages\Finnish.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
; The native build for the machine: ARM64 PCs get the ARM64 build, everything else the x64 one.
Source: "{#SrcArm64}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: IsArm64
Source: "{#SrcX64}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Check: not IsArm64

[InstallDelete]
; Replace the previous version wholesale so no stale runtime files linger.
Type: filesandordirs; Name: "{app}\*"

[Icons]
Name: "{autoprograms}\Journal"; Filename: "{app}\Journal.exe"
Name: "{autodesktop}\Journal"; Filename: "{app}\Journal.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\Journal.exe"; Description: "{cm:LaunchProgram,Journal}"; Flags: nowait postinstall skipifsilent
