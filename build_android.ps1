# Android APK 빌드 스크립트.
#
# 사용자 폴더명이 한글이면 Gradle/ninja 가 실패하므로, 공용 보정 스크립트가
# 이 프로세스의 TEMP/TMP/PUB_CACHE 만 ASCII 경로로 바꾼다(시스템 설정은 건드리지 않음).
# 공용 스크립트가 없는 PC 에서는 아래 폴백을 쓴다.
#
# 사용:  .\build_android.ps1            -> 디버그 APK
#        .\build_android.ps1 -Release   -> 릴리스 APK (기기 종류별로 분리)
param([switch]$Release)

$devEnv = 'C:\myapp\tools\dev-env.ps1'
if (Test-Path $devEnv) {
    . $devEnv
} else {
    $env:TEMP = 'C:\myapp\tmp'
    $env:TMP = 'C:\myapp\tmp'
    $env:PUB_CACHE = 'C:\myapp\tools\pub-cache'
    New-Item -ItemType Directory -Force $env:TEMP | Out-Null
}

Set-Location $PSScriptRoot
flutter pub get
if ($Release) {
    flutter build apk --release --split-per-abi
} else {
    flutter build apk --debug --target-platform android-arm64
}
