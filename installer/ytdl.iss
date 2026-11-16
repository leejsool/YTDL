; YTDL Windows 설치 파일 스크립트 (Inno Setup 6).
; 직접 컴파일하지 말고 tool\build_installer.ps1 을 쓴다(버전을 pubspec.yaml 에서 읽어 넘긴다).
; 관리자 권한 없이 사용자별로 설치한다(%LOCALAPPDATA%\Programs\YTDL).

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "YTDL"
#define AppExe "ytdl.exe"
#define SourceDir "..\build\windows\x64\runner\Release"

[Setup]
; 이 GUID 는 업데이트 때 같은 앱으로 인식하는 키라서 바꾸면 안 된다.
AppId={{7B1D6C0E-4F6A-4E58-9C5D-2A8E3B91F4D7}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=leejsool
AppPublisherURL=https://github.com/leejsool/YTDL
AppSupportURL=https://github.com/leejsool/YTDL/issues
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
OutputDir=..\build\installer
OutputBaseFilename=YTDL-{#AppVersion}-windows-setup
SetupIconFile=..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
; 실행 중인 ytdl.exe 가 있으면 닫고 업데이트한다.
CloseApplications=yes

[Languages]
Name: "korean"; MessagesFile: "compiler:Languages\Korean.isl"

[Tasks]
Name: "desktopicon"; Description: "바탕 화면에 바로가기 만들기"; Flags: unchecked

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: recursesubdirs ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "YTDL 실행"; Flags: nowait postinstall skipifsilent

; 앱 안의 "업데이트"가 /relaunch=1 로 실행했을 때만 새 버전을 다시 띄운다.
Filename: "{app}\{#AppExe}"; Flags: nowait; Check: ShouldRelaunch

[Code]
function ShouldRelaunch: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;

[UninstallDelete]
; 앱이 첫 실행 때 내려받은 yt-dlp/ffmpeg/deno 와 임시 캐시. 받은 음원·영상(저장 폴더)은 건드리지 않는다.
Type: filesandordirs; Name: "{localappdata}\YTDL"
