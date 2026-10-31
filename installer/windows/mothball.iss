; Mothball installer for Windows (Inno Setup 6).
;
; Built by scripts/build-windows.ps1, which passes:
;   /DAppVersion=0.1.2  /DArch=x64|arm64  /DSourceDir=<staged files>  /DOutputDir=<dir>
;
; Installs for the current user only (no admin prompt), into
; %LOCALAPPDATA%\Programs\Mothball:
;   Mothball.exe        the desktop app
;   bin\mothball.exe    the command line tool (added to the user's PATH)
;   bin\mothballw.exe   the same program without a console window, which runs
;                       in the background from the user's startup apps
;
; Upgrades run silently from the app's updater:
;   Mothball-<v>-windows-<arch>-setup.exe /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /RELAUNCH=1

#ifndef AppVersion
  #error AppVersion is required
#endif
#ifndef Arch
  #define Arch "x64"
#endif
#ifndef SourceDir
  #error SourceDir is required
#endif
#ifndef OutputDir
  #define OutputDir "."
#endif

[Setup]
; Never change AppId: Windows uses it to recognise upgrades.
AppId={{B3883D3F-7C21-4105-A537-172930CAB764}
AppName=Mothball
AppVersion={#AppVersion}
AppVerName=Mothball {#AppVersion}
AppPublisher=Hero Momoh
AppPublisherURL=https://github.com/herocodess/mothball
AppSupportURL=https://github.com/herocodess/mothball/issues
AppUpdatesURL=https://github.com/herocodess/mothball/releases
AppCopyright=Copyright (C) 2026 Hero Momoh. MIT License.
VersionInfoVersion={#AppVersion}
VersionInfoProductName=Mothball
VersionInfoDescription=Mothball installer

PrivilegesRequired=lowest
DefaultDirName={localappdata}\Programs\Mothball
DisableDirPage=yes
DisableProgramGroupPage=yes
DisableReadyPage=yes
UsePreviousAppDir=yes
UsePreviousTasks=yes

#if Arch == "arm64"
ArchitecturesAllowed=arm64
ArchitecturesInstallIn64BitMode=arm64
#else
; x64 also runs on Arm PCs through emulation, but they get the Arm64 build.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
#endif
MinVersion=10.0.17763

OutputDir={#OutputDir}
OutputBaseFilename=Mothball-{#AppVersion}-windows-{#Arch}-setup
SetupIconFile={#SourceDir}\app_icon.ico
UninstallDisplayIcon={app}\Mothball.exe
UninstallDisplayName=Mothball
WizardStyle=modern
Compression=lzma2/max
SolidCompression=yes
ChangesEnvironment=yes
CloseApplications=yes
RestartApplications=no
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "addtopath"; Description: "Add the mothball command to PATH (for terminals)"
Name: "desktopicon"; Description: "Create a desktop shortcut"; Flags: unchecked

[Files]
Source: "{#SourceDir}\app\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
Source: "{#SourceDir}\bin\mothball.exe"; DestDir: "{app}\bin"; Flags: ignoreversion
Source: "{#SourceDir}\bin\mothballw.exe"; DestDir: "{app}\bin"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\Mothball"; Filename: "{app}\Mothball.exe"; Comment: "Put idle projects away, get your disk back"
Name: "{autodesktop}\Mothball"; Filename: "{app}\Mothball.exe"; Tasks: desktopicon

[Run]
; Start the background service now and at every login.
Filename: "{app}\bin\mothballw.exe"; Parameters: "service install"; Flags: runhidden waituntilterminated; StatusMsg: "Starting Mothball in the background..."
Filename: "{app}\Mothball.exe"; Description: "Open Mothball"; Flags: nowait postinstall skipifsilent
; After a silent update from the app, open the new version.
Filename: "{app}\Mothball.exe"; Flags: nowait; Check: RelaunchAfterUpdate

[UninstallRun]
; Remove it from the startup apps and stop the background service.
Filename: "{app}\bin\mothballw.exe"; Parameters: "service uninstall"; Flags: runhidden waituntilterminated; RunOnceId: "StopService"

[Code]
const
  EnvKey = 'Environment';

function RelaunchAfterUpdate: Boolean;
begin
  Result := WizardSilent and (ExpandConstant('{param:RELAUNCH|0}') = '1');
end;

procedure StopMothball(App: Boolean);
var
  Code: Integer;
begin
  { The background service holds bin\mothballw.exe open; stop it so the files
    can be replaced or removed. Settings and history are kept. }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM mothballw.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
  if App then
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM Mothball.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopMothball(False);
  Result := '';
end;

{ PATH, for the current user only. Entries are compared case-insensitively. }

function PathIndex(Paths, Dir: String): Integer;
begin
  Result := Pos(';' + Uppercase(Dir) + ';', ';' + Uppercase(Paths) + ';');
end;

procedure AddToPath(Dir: String);
var
  Paths: String;
begin
  if not RegQueryStringValue(HKCU, EnvKey, 'Path', Paths) then
    Paths := '';
  if PathIndex(Paths, Dir) > 0 then
    exit;
  if (Paths <> '') and (Copy(Paths, Length(Paths), 1) <> ';') then
    Paths := Paths + ';';
  RegWriteExpandStringValue(HKCU, EnvKey, 'Path', Paths + Dir);
end;

procedure RemoveFromPath(Dir: String);
var
  Paths: String;
  P: Integer;
begin
  if not RegQueryStringValue(HKCU, EnvKey, 'Path', Paths) then
    exit;
  P := PathIndex(Paths, Dir);
  if P = 0 then
    exit;
  { In ';' + Paths + ';' the match starts at the ';' before Dir, so Dir
    itself starts at index P in Paths. }
  Delete(Paths, P, Length(Dir));
  if (P <= Length(Paths)) and (Copy(Paths, P, 1) = ';') then
    Delete(Paths, P, 1)
  else if (P > 1) and (Copy(Paths, P - 1, 1) = ';') then
    Delete(Paths, P - 1, 1);
  RegWriteExpandStringValue(HKCU, EnvKey, 'Path', Paths);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    if WizardIsTaskSelected('addtopath') then
      AddToPath(ExpandConstant('{app}\bin'))
    else
      RemoveFromPath(ExpandConstant('{app}\bin'));
  end;
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
    StopMothball(True);
  if CurUninstallStep = usPostUninstall then
    RemoveFromPath(ExpandConstant('{app}\bin'));
end;
