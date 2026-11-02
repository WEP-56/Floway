[Setup]
AppId={{APP_ID}}
AppVersion={{APP_VERSION}}
AppVerName={{DISPLAY_NAME}} {{APP_VERSION}}
AppName={{DISPLAY_NAME}}
AppPublisher={{PUBLISHER_NAME}}
AppPublisherURL={{PUBLISHER_URL}}
AppSupportURL={{PUBLISHER_URL}}
AppUpdatesURL={{PUBLISHER_URL}}
; Floway owns its directory and its AppId (see make_config.yaml). Sharing
; either with FLClash made Inno treat an existing FLClash install as a previous
; Floway install: the directory page was skipped, FLClash's directory was
; reused, and its uninstall entry was overwritten.
DefaultDirName={autopf}\Floway
DefaultGroupName={{DISPLAY_NAME}}
DisableProgramGroupPage=yes
; UsePreviousAppDir stays on, but the AppId is Floway's own now, so only a
; previous Floway install can be inherited.
UsePreviousAppDir=yes
UninstallDisplayName={{DISPLAY_NAME}}
UninstallDisplayIcon={app}\{{EXECUTABLE_NAME}}
; Floway kills its own processes below; the Restart Manager must not close or
; restart a neighbouring FLClash that happens to hold files we overwrite.
CloseApplications=no
RestartApplications=no
OutputDir=.
OutputBaseFilename={{OUTPUT_BASE_FILENAME}}
Compression=lzma
SolidCompression=yes
SetupIconFile={{SETUP_ICON_FILE}}
WizardStyle=modern
PrivilegesRequired={{PRIVILEGES_REQUIRED}}
ArchitecturesAllowed={{ARCH}}
ArchitecturesInstallIn64BitMode={{ARCH}}

[Code]
const
  // The AppId Floway shipped with until 2026-11-02: it is FLClash's AppId, so
  // installs made with it live either in FLClash's directory or in a directory
  // that still carries FLClash's uninstall registration.
  LegacyUninstallKey =
    'Software\Microsoft\Windows\CurrentVersion\Uninstall\{728B3532-C74B-4870-9068-BE70FE12A3E6}_is1';

var
  // Directory of a pre-split Floway install, when it holds nothing but Floway.
  LegacyDir: String;
  LegacyDirApplied: Boolean;

procedure KillProcesses;
var
  Processes: TArrayOfString;
  i: Integer;
  ResultCode: Integer;
begin
  Processes := ['Floway.exe', 'FlowayCore.exe', 'FlowayHelperService.exe'];

  for i := 0 to GetArrayLength(Processes)-1 do
  begin
    Exec('taskkill', '/f /im ' + Processes[i], '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

procedure UnregisterHelperService;
var
  HelperPath: String;
  ResultCode: Integer;
begin
  HelperPath := ExpandConstant('{app}\\FlowayHelperService.exe');
  if FileExists(HelperPath) then
  begin
    Exec(HelperPath, 'uninstall', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

procedure ClearStaleProxy;
var
  AppPath: String;
  ResultCode: Integer;
begin
  AppPath := ExpandConstant('{app}\\{{EXECUTABLE_NAME}}');
  if FileExists(AppPath) then
  begin
    Exec(AppPath, '--clear-stale-proxy', '', SW_HIDE, ewWaitUntilTerminated, ResultCode);
  end;
end;

function PointsIntoApp(Value: String): Boolean;
begin
  Result := Pos(Lowercase(AddBackslash(ExpandConstant('{app}'))), Lowercase(Value)) > 0;
end;

// Returns the directory of a Floway install registered under the old shared
// AppId, but only when that directory actually holds Floway.exe.
function LegacyFlowayDir(): String;
var
  Location: String;
begin
  Result := '';
  if not (RegQueryStringValue(HKLM, LegacyUninstallKey, 'InstallLocation', Location) or
          RegQueryStringValue(HKCU, LegacyUninstallKey, 'InstallLocation', Location)) then
  begin
    Exit;
  end;
  Location := RemoveBackslashUnlessRoot(Location);
  if Location = '' then
  begin
    Exit;
  end;
  if FileExists(AddBackslash(Location) + 'Floway.exe') then
  begin
    Result := Location;
  end;
end;

// Drops the stale entry once this version registered the same directory under
// its own AppId, so "Apps & features" does not list Floway twice.
procedure RemoveLegacyUninstallKey;
begin
  if LegacyDir = '' then
  begin
    Exit;
  end;
  if CompareText(RemoveBackslashUnlessRoot(ExpandConstant('{app}')), LegacyDir) <> 0 then
  begin
    Exit;
  end;
  if FileExists(AddBackslash(LegacyDir) + 'FlClash.exe') then
  begin
    Exit;
  end;
  if RegKeyExists(HKLM, LegacyUninstallKey) then
  begin
    RegDeleteKeyIncludingSubkeys(HKLM, LegacyUninstallKey);
  end;
  if RegKeyExists(HKCU, LegacyUninstallKey) then
  begin
    RegDeleteKeyIncludingSubkeys(HKCU, LegacyUninstallKey);
  end;
end;

function InitializeSetup(): Boolean;
begin
  Result := True;
  LegacyDir := LegacyFlowayDir();
  if LegacyDir = '' then
  begin
    Exit;
  end;
  if FileExists(AddBackslash(LegacyDir) + 'FlClash.exe') then
  begin
    // Floway sits inside FLClash's directory: never install back into it, and
    // never claim the entry, because that entry is FLClash's uninstaller.
    Log('Legacy Floway install shares FLClash directory: ' + LegacyDir);
    if not WizardSilent then
    begin
      SuppressibleMsgBox(FmtMessage(CustomMessage('LegacySharedDir'), [LegacyDir]),
        mbError, MB_OK, IDOK);
    end;
    LegacyDir := '';
  end
  else
  begin
    Log('Legacy Floway install found: ' + LegacyDir);
  end;
end;

// A pre-split Floway install keeps its directory, so upgrading replaces it in
// place instead of leaving an orphaned copy behind.
procedure CurPageChanged(CurPageID: Integer);
begin
  if (CurPageID = wpSelectDir) and (LegacyDir <> '') and (not LegacyDirApplied) then
  begin
    LegacyDirApplied := True;
    WizardForm.DirEdit.Text := LegacyDir;
  end;
end;

// The value name is appName and the schemes are protocolSchemes, both in
// lib/common. Only keys that point into this installation are removed, so an
// FLClash that owns clash:// or clashmeta:// keeps its handler.
procedure RemoveUserRegistrations;
var
  Schemes: TArrayOfString;
  Value: String;
  i: Integer;
begin
  if RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{{APP_NAME}}', Value) and PointsIntoApp(Value) then
  begin
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Run', '{{APP_NAME}}');
    RegDeleteValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run', '{{APP_NAME}}');
  end;

  Schemes := ['clash', 'clashmeta', 'floway', 'flclash'];
  for i := 0 to GetArrayLength(Schemes)-1 do
  begin
    if RegQueryStringValue(HKCU, 'Software\Classes\' + Schemes[i] + '\shell\open\command', '', Value) and PointsIntoApp(Value) then
    begin
      RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Classes\' + Schemes[i]);
    end;
  end;
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  UnregisterHelperService;
  KillProcesses;
  Result := '';
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    ClearStaleProxy;
    RemoveLegacyUninstallKey;
  end;
end;

function InitializeUninstall(): Boolean;
begin
  UnregisterHelperService;
  KillProcesses;
  ClearStaleProxy;
  Result := True;
end;

// path_provider names these folders after CompanyName and ProductName in
// windows/runner/Runner.rc. The com.follow\Floway folders are Floway's own
// leftovers from builds that still carried upstream's CompanyName;
// com.follow\clash belongs to FLClash and is never touched here.
procedure RemoveUserData;
begin
  DelTree(ExpandConstant('{userappdata}\Floway\Floway'), True, True, True);
  DelTree(ExpandConstant('{localappdata}\Floway\Floway'), True, True, True);
  DelTree(ExpandConstant('{userappdata}\com.follow\Floway'), True, True, True);
  DelTree(ExpandConstant('{localappdata}\com.follow\Floway'), True, True, True);
  RemoveDir(ExpandConstant('{userappdata}\Floway'));
  RemoveDir(ExpandConstant('{localappdata}\Floway'));
  // RemoveDir only succeeds on an empty directory, so a neighbouring
  // com.follow\clash keeps the shared parent in place.
  RemoveDir(ExpandConstant('{userappdata}\com.follow'));
  RemoveDir(ExpandConstant('{localappdata}\com.follow'));
end;

procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usPostUninstall then
  begin
    RemoveUserRegistrations;
    if not UninstallSilent and (MsgBox(CustomMessage('RemoveUserData'), mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES) then
    begin
      RemoveUserData;
    end;
  end;
end;

[Languages]
{% for locale in LOCALES %}
{% if locale.lang == 'en' %}Name: "english"; MessagesFile: "compiler:Default.isl"{% endif %}
{% if locale.lang == 'hy' %}Name: "armenian"; MessagesFile: "compiler:Languages\\Armenian.isl"{% endif %}
{% if locale.lang == 'bg' %}Name: "bulgarian"; MessagesFile: "compiler:Languages\\Bulgarian.isl"{% endif %}
{% if locale.lang == 'ca' %}Name: "catalan"; MessagesFile: "compiler:Languages\\Catalan.isl"{% endif %}
{% if locale.lang == 'zh' %}
Name: "chineseSimplified"; MessagesFile: {% if locale.file %}{{ locale.file }}{% else %}"compiler:Languages\\ChineseSimplified.isl"{% endif %}
{% endif %}
{% if locale.lang == 'co' %}Name: "corsican"; MessagesFile: "compiler:Languages\\Corsican.isl"{% endif %}
{% if locale.lang == 'cs' %}Name: "czech"; MessagesFile: "compiler:Languages\\Czech.isl"{% endif %}
{% if locale.lang == 'da' %}Name: "danish"; MessagesFile: "compiler:Languages\\Danish.isl"{% endif %}
{% if locale.lang == 'nl' %}Name: "dutch"; MessagesFile: "compiler:Languages\\Dutch.isl"{% endif %}
{% if locale.lang == 'fi' %}Name: "finnish"; MessagesFile: "compiler:Languages\\Finnish.isl"{% endif %}
{% if locale.lang == 'fr' %}Name: "french"; MessagesFile: "compiler:Languages\\French.isl"{% endif %}
{% if locale.lang == 'de' %}Name: "german"; MessagesFile: "compiler:Languages\\German.isl"{% endif %}
{% if locale.lang == 'he' %}Name: "hebrew"; MessagesFile: "compiler:Languages\\Hebrew.isl"{% endif %}
{% if locale.lang == 'is' %}Name: "icelandic"; MessagesFile: "compiler:Languages\\Icelandic.isl"{% endif %}
{% if locale.lang == 'it' %}Name: "italian"; MessagesFile: "compiler:Languages\\Italian.isl"{% endif %}
{% if locale.lang == 'ja' %}Name: "japanese"; MessagesFile: "compiler:Languages\\Japanese.isl"{% endif %}
{% if locale.lang == 'no' %}Name: "norwegian"; MessagesFile: "compiler:Languages\\Norwegian.isl"{% endif %}
{% if locale.lang == 'pl' %}Name: "polish"; MessagesFile: "compiler:Languages\\Polish.isl"{% endif %}
{% if locale.lang == 'pt' %}Name: "portuguese"; MessagesFile: "compiler:Languages\\Portuguese.isl"{% endif %}
{% if locale.lang == 'ru' %}Name: "russian"; MessagesFile: "compiler:Languages\\Russian.isl"{% endif %}
{% if locale.lang == 'sk' %}Name: "slovak"; MessagesFile: "compiler:Languages\\Slovak.isl"{% endif %}
{% if locale.lang == 'sl' %}Name: "slovenian"; MessagesFile: "compiler:Languages\\Slovenian.isl"{% endif %}
{% if locale.lang == 'es' %}Name: "spanish"; MessagesFile: "compiler:Languages\\Spanish.isl"{% endif %}
{% if locale.lang == 'tr' %}Name: "turkish"; MessagesFile: "compiler:Languages\\Turkish.isl"{% endif %}
{% if locale.lang == 'uk' %}Name: "ukrainian"; MessagesFile: "compiler:Languages\\Ukrainian.isl"{% endif %}
{% endfor %}

[CustomMessages]
english.RemoveUserData=Also delete your profiles and settings?
english.LegacySharedDir=An older Floway build was installed into FLClash's directory:%n%n%1%n%nThis version installs into its own directory and overwrites nothing. To clean up, uninstall the old entry first (that entry is FLClash's registration), then reinstall FLClash, then delete the Floway files left in that directory.
chineseSimplified.RemoveUserData=同时删除配置与设置？
chineseSimplified.LegacySharedDir=检测到旧版 Floway 安装在 FLClash 的目录中：%n%n%1%n%n本版本会装到独立目录，不再覆盖它。清理旧版本请按顺序操作：先在「应用和功能」里卸载旧条目（那条记录属于 FLClash），再重新安装 FLClash，最后删除该目录里剩下的 Floway 文件。

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: {% if CREATE_DESKTOP_ICON != true %}unchecked{% else %}checkedonce{% endif %}
[Files]
Source: "{{SOURCE_DIR}}\\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
; NOTE: Don't use "Flags: ignoreversion" on any shared system files

[Icons]
Name: "{autoprograms}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"
Name: "{autodesktop}\\{{DISPLAY_NAME}}"; Filename: "{app}\\{{EXECUTABLE_NAME}}"; Tasks: desktopicon
[Run]
Filename: "{app}\\{{EXECUTABLE_NAME}}"; Description: "{cm:LaunchProgram,{{DISPLAY_NAME}}}"; Flags: {% if PRIVILEGES_REQUIRED == 'admin' %}runascurrentuser{% endif %} nowait postinstall skipifsilent
