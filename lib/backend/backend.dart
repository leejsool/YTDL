import 'dart:io';

import '../models.dart';
import 'android_backend.dart';
import 'desktop_backend.dart';

typedef SetupCallback = void Function(String message, double? progress);

/// 플랫폼별 다운로드 엔진 인터페이스.
/// - Windows : yt-dlp.exe + ffmpeg.exe 를 직접 실행
/// - Android : youtubedl-android(yt-dlp + ffmpeg 내장) 를 플랫폼 채널로 호출
abstract class Backend {
  /// 엔진 준비(첫 실행 시 필요한 파일 내려받기, 업데이트 확인 등).
  Future<void> prepare(SetupCallback onStatus);

  Future<MediaInfo> fetchInfo(String url);

  /// 원본 음량을 측정하고 목표 음량까지 필요한 dB를 반환한다.
  Future<double> measureGain(
    String source,
    CancelToken token, {
    bool remote = false,
    double? startSec,
    double? endSec,
  });

  Future<DownloadResult> download(
    String url,
    DownloadOptions options,
    void Function(DownloadProgress) onProgress,
    CancelToken token,
  );

  /// 이미 저장한 음원 파일에서 [startSec]~[endSec] 만 잘라 새 파일([outBaseName].확장자)로 저장한다.
  /// 음량 조절([gain])이 없으면 재인코딩 없이 그대로 복사(-c copy)하므로 음질 손실이 없고 빠르다.
  /// 음량을 바꾸면 같은 형식으로 다시 인코딩해서 저장한다.
  Future<DownloadResult> trimAudio(
    String srcPath,
    double startSec,
    double endSec,
    String outBaseName, {
    AudioGain gain = const AudioGain.none(),
  });

  /// yt-dlp 엔진을 최신으로 업데이트하고 결과 문구를 돌려준다.
  Future<String> updateEngine();

  /// 저장 위치 안내 문구.
  String get saveLocationLabel;

  /// 저장 폴더를 사용자가 직접 바꿀 수 있는지(Windows만).
  bool get canChooseFolder => false;
  Future<void> chooseFolder() async {}

  /// 결과 파일이 있는 폴더를 열 수 있는지(Windows만).
  bool get canReveal => false;

  /// 결과 파일이 있는 폴더를 연다(Windows만).
  Future<void> reveal(DownloadResult result) async {}

  /// 다른 앱(유튜브 앱 등)에서 공유로 넘어온 텍스트(Android만).
  Future<String?> takeInitialSharedText() async => null;
  void Function(String text)? onSharedText;
}

Backend createBackend() =>
    Platform.isAndroid ? AndroidBackend() : DesktopBackend();
