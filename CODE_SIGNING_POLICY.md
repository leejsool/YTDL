# Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io), certificate by [SignPath Foundation](https://signpath.org).

Windows 설치 파일(`YTDL-<버전>-windows-setup.exe`)과 그 안의 `ytdl.exe` 는 위 서비스로 서명한다.

## 서명 대상

- 이 저장소의 소스에서 GitHub Actions([windows-build.yml](.github/workflows/windows-build.yml))가 자동으로 빌드한 파일만 서명한다.
- 제품 이름은 항상 `YTDL`, 버전은 `pubspec.yaml` 의 `version` 과 같다.
- 포함된 외부 구성요소(Flutter 엔진, 플러그인 DLL)는 각 프로젝트가 배포한 그대로이며 이 프로젝트가 서명하지 않는다.

## 역할

| 역할 | 담당 |
|---|---|
| Authors (소스 변경) | [leejsool](https://github.com/leejsool) |
| Reviewers (외부 기여 검토) | [leejsool](https://github.com/leejsool) |
| Approvers (서명 요청 승인) | [leejsool](https://github.com/leejsool) |

모든 담당자는 GitHub 와 SignPath 에 다단계 인증(MFA)을 쓴다. 서명은 릴리스마다 승인자가 직접 승인한다.

## 개인정보

YTDL 은 사용자 정보를 수집하거나 개발자에게 보내지 않는다. 앱이 하는 네트워크 통신은 다음뿐이다.

- 사용자가 입력한 유튜브 링크의 영상 정보·미디어를 내려받기 위해 YouTube 와 통신한다(yt-dlp 사용).
- 처음 실행할 때, 그리고 하루에 한 번 yt-dlp / ffmpeg / deno 를 내려받거나 업데이트한다.
- 옵션 탭의 "업데이트 확인"을 누르면 GitHub(`api.github.com`)에서 이 저장소의 최신 릴리스 정보를 가져온다. 누르지 않으면 통신하지 않는다.

받은 파일과 설정은 사용자의 PC 안에만 저장된다.

## 설치와 제거

설치 파일은 관리자 권한 없이 `%LOCALAPPDATA%\Programs\YTDL` 에 설치하며, 설정 > 앱에서 제거할 수 있다. 제거하면 앱이 받아 둔 `%LOCALAPPDATA%\YTDL`(yt-dlp, 캐시)도 함께 지운다. 사용자가 받은 음원·영상은 지우지 않는다.

## 문제 신고

잘못 서명되었거나 악성으로 의심되는 파일은 [이슈](https://github.com/leejsool/YTDL/issues)로 알려 주세요.
