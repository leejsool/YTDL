# Windows 설치 파일(setup.exe) 만들기: flutter build windows -> Inno Setup 컴파일.
# 결과: build\installer\YTDL-<버전>-windows-setup.exe
# Inno Setup 은 C:\myapp\tools\innosetup (또는 기본 설치 경로)에 있어야 한다.
param([switch]$SkipBuild)

$root = Split-Path $PSScriptRoot -Parent
Set-Location $root

$devEnv = 'C:\myapp\tools\dev-env.ps1'
if (Test-Path $devEnv) { . $devEnv }

$iscc = @(
    'C:\myapp\tools\innosetup\ISCC.exe',
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe'
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup(ISCC.exe)을 찾을 수 없다.' }

# pubspec 의 "version: 1.0.0+1" 에서 1.0.0 만 쓴다.
$ver = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value

if (-not $SkipBuild) {
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows 실패' }
}

& $iscc "/DAppVersion=$ver" installer\ytdl.iss
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup 컴파일 실패' }
Get-ChildItem build\installer
