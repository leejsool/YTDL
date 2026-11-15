import 'dart:io';

import '../models.dart';
import 'ytdlp_args.dart';
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

  /// 이미 가진 영상 파일에서 [startSec]~[endSec] 만 잘라 새 파일([outBaseName].확장자)로 저장한다.
  /// [reencode] 가 false 면 복사(빠르고 무손실, 시작이 키프레임 단위), true 면 다시 인코딩(정확, 느림, 항상 mp4).
  Future<DownloadResult> trimVideo(
    String srcPath,
    double startSec,
    double endSec,
    String outBaseName, {
    bool reencode = false,
  }) => throw UnimplementedError();

  /// 미리듣기용: yt-dlp 로 [url] 의 소리를 받아(인자는 [args]) 임시 파일 경로를 돌려준다.
  Future<String> previewDownload(String url, List<String> args) =>
      throw UnimplementedError();

  final Map<String, Future<String>> _fullAudio = {};

  /// 미리듣기 결과 파일 이름에 쓸 꼬리표. 같은 이름의 다른 소리(다른 영상)가 섞이지 않게
  /// 주소/경로뿐 아니라 파일의 크기와 수정 시각까지 넣는다.
  String previewFileKey(String src) {
    var id = src;
    if (!src.startsWith('http')) {
      try {
        final f = File(src);
        id = '$src|${f.lengthSync()}|${f.lastModifiedSync().microsecondsSinceEpoch}';
      } catch (_) {}
    }
    return id.hashCode.toUnsigned(32).toRadixString(36);
  }

  /// 미리듣기용: 소리 전체를 한 번 받아 둔다(같은 영상은 다시 받지 않는다).
  ///
  /// [audioUrl] (영상 조회 때 알아 둔 소리 스트림 주소)이 있으면 그걸 10MB 씩 나눠서 직접 받는다.
  /// 유튜브는 한 줄로 길게 읽는 연결(ffmpeg 등)은 속도를 실시간으로 묶지만, 구간(Range)으로 나눠 받으면
  /// 제한이 없어서 15분짜리가 1초 남짓에 받아진다. 이 방법은 yt-dlp 를 다시 돌리지 않아 영상 분석 시간(3~5초)도 아낀다.
  /// 주소가 만료됐거나 막혀 있으면 yt-dlp 로 받는다.
  Future<String> previewFull(String url, {String? audioUrl}) {
    return _fullAudio[url] ??= _fetchFull(url, audioUrl).catchError((Object e) {
      _fullAudio.remove(url);
      throw e;
    });
  }

  /// 미리듣기용으로 이미 받아 둔(또는 받는 중인) 전체 소리 파일. 없거나 받기에 실패했으면 null.
  /// 자동 음량 분석이 같은 소리를 yt-dlp 로 다시 받지 않고 이 파일을 쓰게 하려고 둔다.
  Future<String?> cachedFullAudio(String url) async {
    final pending = _fullAudio[url];
    if (pending == null) return null;
    try {
      final path = await pending;
      return File(path).existsSync() ? path : null;
    } catch (_) {
      return null;
    }
  }

  Future<String> _fetchFull(String url, String? audioUrl) async {
    if (audioUrl != null) {
      try {
        return await _downloadChunked(audioUrl);
      } catch (_) {
        // 아래 yt-dlp 로 다시 시도한다.
      }
    }
    return previewDownload(url, buildPreviewFullArgs());
  }

  Future<String> _downloadChunked(String url) async {
    const chunk = 10 * 1024 * 1024;
    final uri = Uri.parse(url);
    final mime = uri.queryParameters['mime'] ?? '';
    final ext = mime.contains('webm') ? 'webm' : (mime.contains('mp4') ? 'm4a' : 'audio');
    final dir = await Directory('${Directory.systemTemp.path}${Platform.pathSeparator}ytdl_preview_full')
        .create(recursive: true);
    // 오래된 받은 파일 정리(1시간 지난 것)
    for (final e in dir.listSync()) {
      try {
        if (DateTime.now().difference(e.statSync().modified).inMinutes > 60) e.deleteSync();
      } catch (_) {}
    }
    final file = File('${dir.path}${Platform.pathSeparator}full_${DateTime.now().microsecondsSinceEpoch}.$ext');
    final sink = file.openWrite();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      var pos = 0;
      int? total;
      while (total == null || pos < total) {
        final req = await client.getUrl(uri);
        req.headers
          ..set(HttpHeaders.rangeHeader, 'bytes=$pos-${pos + chunk - 1}')
          ..set(HttpHeaders.userAgentHeader, 'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130 Mobile Safari/537.36');
        final res = await req.close().timeout(const Duration(seconds: 30));
        if (res.statusCode != 206 && res.statusCode != 200) {
          await res.drain<void>();
          throw HttpException('HTTP ${res.statusCode}');
        }
        final cr = res.headers.value(HttpHeaders.contentRangeHeader); // bytes 0-10485759/20525388
        total ??= int.tryParse(cr?.split('/').last ?? '') ?? (res.statusCode == 200 ? res.contentLength : null);
        var got = 0;
        await for (final data in res.timeout(const Duration(seconds: 30))) {
          sink.add(data);
          got += data.length;
        }
        pos += got;
        if (got == 0 || res.statusCode == 200 || total == null) break; // 한 번에 다 받았거나 끝
      }
      await sink.close();
      if (pos == 0) throw const HttpException('빈 응답');
      return file.path;
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (file.existsSync()) file.deleteSync();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  /// 미리듣기용: 유튜브 영상의 [startSec]~[endSec] 소리를 임시 파일로 돌려준다.
  /// 전체를 받아 폰/PC 안에서 잘라 쓰고, 그게 안 되면 구간만 받는 방법을 쓴다.
  Future<String> previewSegment(String url, double startSec, double endSec, {String? audioUrl}) async {
    try {
      final full = await previewFull(url, audioUrl: audioUrl);
      return await previewGain(
        full,
        const AudioGain.none(),
        startSec: startSec,
        endSec: endSec,
        ext: 'wav', // 압축 없는 wav 라 자르기가 거의 즉시 끝난다
      );
    } catch (first) {
      try {
        return await previewDownload(url, buildPreviewSegmentArgs(startSec, endSec));
      } catch (second) {
        String clean(Object e) => e.toString().replaceFirst('Exception: ', '');
        throw Exception('${clean(first)} / 구간만 받는 방법도 실패: ${clean(second)}');
      }
    }
  }

  /// 미리듣기용: [srcPath] (의 [startSec]~[endSec], 없으면 전체)에 음량 조절을 적용한
  /// 재생용 임시 파일 경로를 돌려준다. [ext] 가 'wav' 이면 압축하지 않아 훨씬 빠르게(4분짜리 0.6초 vs 6.7초) 만들지만 파일이 크다. 조절이 없고 그대로 재생할 수 있으면 원본 경로를 그대로 돌려준다.
  Future<String> previewGain(
    String srcPath,
    AudioGain gain, {
    double? startSec,
    double? endSec,
    String ext = 'm4a',
  }) => throw UnimplementedError();

  /// yt-dlp 엔진을 최신으로 업데이트하고 결과 문구를 돌려준다.
  Future<String> updateEngine();

  /// 저장 위치 안내 문구.
  String get saveLocationLabel;

  /// Android: 저장 폴더 이름(Music/<이름>, Movies/<이름>). Windows 는 폴더를 직접 고르므로 쓰지 않는다.
  String get folderName => 'YTDL';
  bool get canRenameFolder => false;
  Future<void> setFolderName(String name) async {}

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
