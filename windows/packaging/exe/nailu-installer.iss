#ifndef NaiLuVersion
  #define NaiLuVersion "0.1.2"
#endif
#ifndef NaiLuSource
  #define NaiLuSource "..\..\..\build\windows\x64\runner\Release"
#endif

[Setup]
AppId={{950ED441-738C-4F6D-BDBD-6A74C32B7DD4}
AppName=奈鹿 NaiLu
AppVersion={#NaiLuVersion}
AppPublisher=奈鹿 NaiLu
AppPublisherURL=https://nailu.pro
AppSupportURL=https://nailu.pro
DefaultDirName={localappdata}\Programs\NaiLu
DefaultGroupName=奈鹿 NaiLu
DisableDirPage=no
DisableProgramGroupPage=yes
LicenseFile=..\..\..\LICENSE
OutputBaseFilename=NaiLu-{#NaiLuVersion}-windows-x64-setup
SetupIconFile=..\..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\NaiLu.exe
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
Compression=lzma2
SolidCompression=yes
CloseApplications=yes
RestartApplications=no
AlwaysShowDirOnReadyPage=yes

[Languages]
Name: "chineseSimplified"; MessagesFile: "ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "快捷方式"; Flags: checkedonce

[Files]
Source: "{#NaiLuSource}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
#ifdef NaiLuWebViewBootstrapper
Source: "{#NaiLuWebViewBootstrapper}"; DestName: "MicrosoftEdgeWebview2Setup.exe"; Flags: dontcopy
#endif

[Icons]
Name: "{autoprograms}\奈鹿 NaiLu"; Filename: "{app}\NaiLu.exe"
Name: "{autodesktop}\奈鹿 NaiLu"; Filename: "{app}\NaiLu.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\NaiLu.exe"; Description: "启动奈鹿 NaiLu"; Flags: nowait postinstall skipifsilent

[Code]
var
  LocationPage: TInputOptionWizardPage;

function WebViewAvailable(): Boolean;
var
  Version: String;
  Key: String;
begin
  Key := 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}';
  Result := (RegQueryStringValue(HKCU, Key, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0'))
    or (RegQueryStringValue(HKLM32, Key, 'pv', Version) and (Version <> '') and (Version <> '0.0.0.0'));
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  ResultCode: Integer;
begin
#ifdef NaiLuWebViewBootstrapper
  if (CurStep = ssPostInstall) and not WebViewAvailable() then
  begin
    WizardForm.StatusLabel.Caption := '正在安装 Microsoft WebView2 登录验证组件，请保持联网…';
    ExtractTemporaryFile('MicrosoftEdgeWebview2Setup.exe');
    if not Exec(ExpandConstant('{tmp}\MicrosoftEdgeWebview2Setup.exe'), '/silent /install', '',
      SW_HIDE, ewWaitUntilTerminated, ResultCode) or not WebViewAvailable() then
      MsgBox('Microsoft WebView2 安装尚未完成。请联网后安装该组件，再使用奈鹿登录和注册。', mbInformation, MB_OK);
  end;
#endif
end;

procedure InitializeWizard();
begin
  LocationPage := CreateInputOptionPage(wpWelcome,
    '选择安装位置', '奈鹿可以安装在应用目录，也可以放到桌面。',
    '请选择安装方式，下一步仍可修改具体文件夹：', True, False);
  LocationPage.Add('安装到本机应用目录（推荐）');
  LocationPage.Add('安装到桌面上的“奈鹿 NaiLu”文件夹');
  LocationPage.SelectedValueIndex := 0;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
begin
  if CurPageID = LocationPage.ID then
  begin
    if LocationPage.SelectedValueIndex = 1 then
      WizardForm.DirEdit.Text := ExpandConstant('{autodesktop}\奈鹿 NaiLu')
    else
      WizardForm.DirEdit.Text := ExpandConstant('{localappdata}\Programs\NaiLu');
  end;
  Result := True;
end;
