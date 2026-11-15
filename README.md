# YTDL

유튜브 음원/영상 다운로더 (Windows + Android, Flutter 하나로 통일). 음원은 필요한 구간만 잘라서 저장할 수 있다.

## 주요 기능

- 음원(MP3/M4A/OPUS) · 영상(MP4) 다운로드, 받기 전에 **구간만** 잘라서 저장
- 화질·형식 버튼마다 **예상 용량** 표시(`lib/util/size_estimate.dart`; yt-dlp 가 실제로 고르는 포맷과 같은 규칙으로 계산, 구간을 켜면 비율만큼 줄여서 표시)
- 아래쪽 탭이 두 개: **다운로드** / **편집**
- **편집 탭**(`lib/screens/edit_page.dart`, `lib/widgets/audio_editor.dart`): 컴퓨터·폰에 있는 아무 음원(MP3, M4A, AAC, FLAC, WAV, OGG, OPUS, WMA)이나
  방금 받은 음원을 열어 듣고, 구간을 잘라 새 파일로 저장한다.
  - 파일 여는 법: "음원 파일 선택", 최근 파일 목록(앱을 껐다 켜도 유지), 다운로드 탭의 "편집하기" 버튼
  - 재생/일시정지, 위치 이동, 구간을 슬라이더·시간 입력(0.1초 단위)·"여기부터/여기까지"로 고르기
  - 선택 구간 / 시작 부분 / 끝 부분 듣기(구간 끝에서 자동 정지)
  - "새 파일로 저장": 재인코딩 없이 복사(`-c copy`)라 음질 손실이 없고 원본 파일은 그대로 둔다. 새 파일이 다시 편집 대상이 되어 계속 더 자를 수 있다
  - 저장 위치: Windows 는 **원본 파일과 같은 폴더**, Android 는 `Music/YTDL`
  - 유튜브에서 받은 파일은 "원본 영상 기준 0:05.0 ~ 0:12.0"처럼 원본 시각을 보여 주고, 이름도 `Title (cut 0m07.5s-0m09.5s).mp3` 로 원본 기준 시각을 쓴다.
    이 이름의 파일을 다시 열면 원본 기준 구간을 이어받는다. 이름에 정보가 없는 일반 파일은 파일 안의 시각만 보여 준다(처음 자른 뒤부터 "원본 파일" 기준을 함께 표시)
- Android: 유튜브 앱 "공유" → YTDL 로 링크 전달

## 구조

| 위치 | 역할 |
|---|---|
| `lib/screens`, `lib/widgets` | 공통 UI (링크 조회 → 음원/영상 선택 → 구간 선택 → 다운로드) |
| `lib/backend/ytdlp_args.dart` | 두 플랫폼이 똑같이 쓰는 yt-dlp 인자 생성 + 진행률 해석 |
| `lib/backend/desktop_backend.dart` | Windows: `%LOCALAPPDATA%\YTDL\bin` 의 yt-dlp / ffmpeg / deno 를 직접 실행. 첫 실행 때 자동으로 내려받고 하루 한 번 yt-dlp 업데이트 |
| `lib/backend/android_backend.dart` + `android/.../MainActivity.kt` | Android: youtubedl-android(yt-dlp+python+ffmpeg 내장)를 플랫폼 채널로 호출. 결과는 MediaStore 로 `Music/YTDL`, `Movies/YTDL` 에 저장(권한 불필요). 이미 받은 파일을 다시 자를 때는 내장 `libffmpeg.so` 를 직접 실행(`LD_LIBRARY_PATH` 에 `ffmpeg/usr/lib`, `python/usr/lib`, 앱 네이티브 폴더 지정) |
| `test/` | 단위 테스트(예상 용량은 실제 yt-dlp 응답 `test/fixtures` 와 대조, 이름·시간 변환) |
| `tool/engine_check.dart` | 앱이 쓰는 인자로 실제 다운로드·자르기를 검증하는 스크립트 |

## 빌드

```powershell
.\build_android.ps1            # 디버그 APK -> build\app\outputs\flutter-apk\app-debug.apk
.\build_android.ps1 -Release   # 릴리스 APK (ABI 별 분리)
flutter build windows          # Visual Studio(C++ 데스크톱 워크로드) 설치 필요
```

`build_android.ps1` 은 한글 사용자 폴더 때문에 생기는 Gradle/ninja 오류를 피하려고
`TEMP`/`TMP`(→ `C:\myapp\tmp`)와 `PUB_CACHE`(→ `C:\myapp\tools\pub-cache`)를 이 프로세스에서만 ASCII 경로로 지정한다.

## Android 폰에 설치

폰에서 개발자 옵션 → USB 디버깅을 켜고 PC에 연결한 뒤:

```powershell
.\build_android.ps1
C:\android\sdk\platform-tools\adb.exe install -r build\app\outputs\flutter-apk\app-debug.apk
```

받은 파일은 폰의 `Music/YTDL`(음원), `Movies/YTDL`(영상)에 저장된다. 유튜브 앱에서 "공유 → YTDL" 로 링크를 바로 보낼 수 있다.
디버그 APK 는 크다(약 235MB). 배포용은 `.\build_android.ps1 -Release` 로 ABI 별 APK 를 만든다.

## Windows 앱 자동 테스트

실제 앱을 띄워 첫 실행(도구 내려받기) → 링크 조회 → MP3 구간 자르기 → 영상 다운로드까지 확인한다. 인터넷이 필요하다.

```powershell
. C:\myapp\tools\dev-env.ps1     # 한글 사용자 폴더 우회(필요한 PC에서만 동작)
flutter test integration_test/windows_flow_test.dart -d windows
```

> **주의:** 통합 테스트는 `build\windows\...\Debug\ytdl.exe` 를 **테스트용 exe 로 덮어쓴다**.
> 이 exe 를 직접 실행하면 테스트 지휘자를 기다리느라 창이 뜨지 않는다(프로세스만 떠 있음).
> 테스트 뒤에 앱을 직접 실행하려면 `flutter build windows` 또는 `flutter run -d windows` 로 다시 빌드할 것.

## 아이콘 바꾸기

```powershell
.\tool\make_icon.ps1                 # assets\icon 에 원본 PNG 생성 (디자인은 이 스크립트 안)
dart run flutter_launcher_icons      # Android / Windows 아이콘 적용
```

## 재생 지연(첫 재생이 버벅이는지) 측정

```powershell
flutter test integration_test/audio_latency_test.dart  -d windows   # 플레이어 자체: 갓 로드 vs 두 번째 재생
flutter test integration_test/editor_latency_test.dart -d windows   # 편집기 화면에서 ▶ 눌렀을 때
# 소리 없이 먼저 한 번 돌려 두는 "준비운동"은 기본 꺼짐(Windows 에서 효과 없음). 켜 보려면 --dart-define=PRIME=true
```

Android 는 샘플 mp3 를 `adb push latency_sample.mp3 /sdcard/Android/data/com.ytdl.ytdl/files/latency_sample.mp3` 로 넣고 `-d <기기>` 로 돌린다.

## 엔진 검증

```powershell
dart run tool/engine_check.dart C:\myapp\tools\ytdlp C:\myapp\tmp\engine_out "https://www.youtube.com/watch?v=jNQXAC9IVRw"
```

## 참고

- 유튜브가 바뀌어 다운로드가 실패하면 앱 상단의 업데이트 버튼(엔진 업데이트)을 누른다.
- 본인이 권리를 가진 콘텐츠 또는 다운로드가 허용된 콘텐츠에만 사용할 것. 유튜브 약관은 허가 없는 다운로드를 금지한다.
