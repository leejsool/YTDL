import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../models.dart';
import '../util/names.dart';
import '../util/oembed.dart';
import 'gain_args.dart';
import 'ytdlp_args.dart';
import 'android_backend.dart';
import 'desktop_backend.dart';

typedef SetupCallback = void Function(String message, double? progress);

/// 큰 JSON(재생목록은 수백 KB)을 화면 스레드를 막지 않게 따로 읽는다.
Future<Map<String, dynamic>> decodeJsonOffThread(String raw) =>
    Isolate.run(() => jsonDecode(raw) as Map<String, dynamic>);

/// 플랫폼별 다운로드 엔진 인터페이스.
/// - Windows : yt-dlp.exe + ffmpeg.exe 를 직접 실행
/// - Android : youtubedl-android(yt-dlp + ffmpeg 내장) 를 플랫폼 채널로 호출
abstract class Backend {
  /// 엔진 준비(첫 실행 시 필요한 파일 내려받기, 업데이트 확인 등).
  Future<void> prepare(SetupCallback onStatus);

  Future<MediaInfo> fetchInfo(String url);

  // ---------------------------------------------------------------- 엔진 업데이트와 작업이 겹치지 않게
  int _engineBusy = 0;
  Future<void> _engineHold = Future.value();

  /// yt-dlp 를 쓰는 작업을 감싼다. 엔진 업데이트가 돌고 있으면 끝날 때까지 기다렸다가 시작하고
  /// (실행 중인 yt-dlp 를 교체하면 안 된다), 작업 중이라는 것을 표시해 그동안 업데이트가 시작되지 않게 한다.
  Future<T> withEngine<T>(Future<T> Function() op) async {
    while (true) {
      final hold = _engineHold;
      await hold;
      if (identical(hold, _engineHold)) break;
    }
    _engineBusy++;
    try {
      return await op();
    } finally {
      _engineBusy--;
    }
  }

  /// 엔진 업데이트를 "앱을 켜고 조금 지난 뒤, 아무 작업도 없을 때" 뒤에서 돌린다.
  /// 켜자마자 돌리면 그날 첫 조회가 업데이트가 끝날 때까지(수 초~수십 초) 기다리게 된다.
  void scheduleEngineUpdate(
    Future<void> Function() update, {
    Duration delay = const Duration(seconds: 20),
  }) {
    unawaited(() async {
      await Future<void>.delayed(delay);
      while (_engineBusy > 0) {
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      _engineHold = update().catchError((Object _) {});
    }());
  }

  /// 재생목록 주소의 영상 목록을 읽는다(영상마다 자세한 분석은 하지 않아 수 초 안에 끝난다).
  /// 너무 길면 앞의 [limit] 개만 읽는다.
  Future<PlaylistInfo> fetchPlaylist(String url, {int limit = 200}) =>
      throw UnimplementedError();

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

  /// 받아 둔 소리를 두는 폴더. 조회하자마자 여기에 소리 전체를 받아 두고 미리듣기·음량 분석·저장에 같이 쓴다.
  /// [audioCacheDays] 일이 지난 파일은 지운다. (Windows 는 앱 폴더 아래로 바꾼다.)
  Directory get audioCacheDir => Directory(
    '${Directory.systemTemp.path}${Platform.pathSeparator}ytdl_audio_cache',
  );

  /// 받아 둔 소리를 보관하는 날 수.
  static const audioCacheDays = 3;

  bool _cacheCleaned = false;

  /// 오래된 받아 둔 소리를 지운다(앱을 켠 뒤 처음 한 번). 받다 만 조각(.part)은 한 시간 지나면 지운다.
  void cleanAudioCache({bool force = false}) {
    if (_cacheCleaned && !force) return;
    _cacheCleaned = true;
    try {
      final dir = audioCacheDir;
      if (!dir.existsSync()) return;
      final now = DateTime.now();
      for (final e in dir.listSync()) {
        try {
          final age = now.difference(e.statSync().modified);
          final limit = e.path.endsWith('.part')
              ? const Duration(hours: 1)
              : const Duration(days: audioCacheDays);
          if (age > limit) e.deleteSync(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
  }

  static String _streamTag(String? audioUrl) {
    if (audioUrl == null) return '';
    try {
      return Uri.parse(audioUrl).queryParameters['itag'] ?? '';
    } catch (_) {
      return '';
    }
  }

  /// 소리 전체를 한 번 받아 둔다(같은 영상·같은 스트림은 다시 받지 않고, 앱을 다시 켜도 남아 있다).
  ///
  /// [audioUrl] (영상 조회 때 알아 둔 소리 스트림 주소)이 있으면 그걸 10MB 씩 나눠서 직접 받는다.
  /// 유튜브는 한 줄로 길게 읽는 연결(ffmpeg 등)은 속도를 실시간으로 묶지만, 구간(Range)으로 나눠 받으면
  /// 제한이 없어서 15분짜리가 1초 남짓에 받아진다. 이 방법은 yt-dlp 를 다시 돌리지 않아 영상 분석 시간(3~5초)도 아낀다.
  /// 주소가 만료됐거나 막혀 있으면 yt-dlp 로 받는다.
  ///
  /// [exact] 가 false 면(미리듣기·음량 분석) 이 영상의 소리가 어떤 스트림으로든 이미 있으면 그걸 쓴다.
  /// true 면(저장) 꼭 [audioUrl] 의 스트림을 받는다.
  Future<String> previewFull(String url, {String? audioUrl, bool exact = false}) async {
    if (!exact) {
      final any = await cachedFullAudio(url);
      if (any != null) return any;
    }
    final key = '$url|${_streamTag(audioUrl)}';
    for (var attempt = 0; ; attempt++) {
      final pending = _fullAudio[key] ??= _fetchFull(url, audioUrl);
      try {
        final path = await pending;
        // 받아 둔 뒤 파일이 지워졌으면(임시 폴더 정리 등) 한 번 다시 받는다.
        if (attempt > 0 || File(path).existsSync()) return path;
      } catch (_) {
        if (identical(_fullAudio[key], pending)) _fullAudio.remove(key);
        rethrow;
      }
      if (identical(_fullAudio[key], pending)) _fullAudio.remove(key);
    }
  }

  /// 이 영상의 소리로 이미 받아 둔(또는 받는 중인) 파일. 없거나 받기에 실패했으면 null.
  /// 미리듣기와 자동 음량 분석이 같은 소리를 다시 받지 않게 하려고 둔다.
  Future<String?> cachedFullAudio(String url) async {
    final prefix = '$url|';
    for (final key in _fullAudio.keys.where((k) => k.startsWith(prefix)).toList()) {
      try {
        final path = await _fullAudio[key];
        if (path != null && File(path).existsSync()) return path;
      } catch (_) {}
    }
    return null;
  }

  Future<String> _fetchFull(String url, String? audioUrl) async {
    if (audioUrl != null) {
      try {
        return await _downloadChunked(url, audioUrl);
      } catch (_) {
        // 아래 yt-dlp 로 다시 시도한다.
      }
    }
    return previewDownload(url, buildPreviewFullArgs());
  }

  Future<String> _downloadChunked(String pageUrl, String url) async {
    const chunk = 10 * 1024 * 1024;
    final uri = Uri.parse(url);
    final mime = uri.queryParameters['mime'] ?? '';
    final ext = mime.contains('webm') ? 'webm' : (mime.contains('mp4') ? 'm4a' : 'audio');
    final dir = await audioCacheDir.create(recursive: true);
    cleanAudioCache();
    final name = '${youtubeVideoId(pageUrl) ?? stableHash(pageUrl)}_${_streamTag(url)}.$ext';
    final file = File('${dir.path}${Platform.pathSeparator}$name');
    // 전에 받아 둔 게 있으면 그대로 쓴다(보관 기간이 다시 시작되게 시각만 고친다).
    if (file.existsSync() && file.lengthSync() > 0) {
      try {
        file.setLastModifiedSync(DateTime.now());
      } catch (_) {}
      return file.path;
    }
    // 다 받은 뒤에 제 이름으로 바꿔서, 받다가 끊긴 반쪽짜리를 쓰는 일이 없게 한다.
    final part = File('${file.path}.${DateTime.now().microsecondsSinceEpoch}.part');
    final sink = part.openWrite();
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
      if (total != null && total > 0 && pos < total) throw const HttpException('받다가 끊겼습니다');
      if (file.existsSync()) file.deleteSync();
      return (await part.rename(file.path)).path;
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}
      if (part.existsSync()) part.deleteSync();
      rethrow;
    } finally {
      client.close(force: true);
    }
  }

  // ---------------------------------------------------------------- 음원을 기기 안에서 만들기
  /// 받아 둔 소리 [srcPath] 로 [outBaseName].[ext] 를 만들어 저장 위치에 둔다.
  /// [inArgs] 는 ffmpeg 입력 앞(-ss/-t), [outArgs] 는 출력 쪽(코덱·필터·태그) 인자.
  Future<DownloadResult> convertAudio(
    String srcPath,
    String outBaseName,
    String ext, {
    List<String> inArgs = const [],
    List<String> outArgs = const [],
    CancelToken? token,
  }) => throw UnimplementedError();

  /// 음원을 yt-dlp 없이 만든다: 조회 때 알아 둔 소리 스트림을 받아 두고(대개 조회 직후 이미 받아 놓았다)
  /// 기기 안에서 자르기·음량 조절·변환을 한 번에 한다.
  /// 구간만 받기는 유튜브가 실시간 속도로 묶어서 4분 구간에 2분이 걸리지만, 이 방법은 몇 초면 끝난다.
  /// 조건이 안 맞거나 실패하면 null 을 돌려주고, 그러면 부르는 쪽이 예전처럼 yt-dlp 로 받는다.
  Future<DownloadResult?> downloadAudioLocally(
    String url,
    DownloadOptions o,
    void Function(DownloadProgress) onProgress,
    CancelToken token,
  ) async {
    final info = o.info;
    if (o.kind != MediaKind.audio || info == null) return null;
    final audioUrl = info.audioUrlFor(o.audioFormat);
    if (audioUrl == null) return null;
    try {
      onProgress(const DownloadProgress(stage: '음원 받는 중…'));
      final src = await previewFull(url, audioUrl: audioUrl, exact: true);
      if (token.cancelled) throw CancelledException();
      onProgress(
        DownloadProgress(stage: o.gain.isActive ? '음량 조절 중…' : '변환 중…'),
      );
      final name =
          '${fileNameFromTitle(info.title)}${o.gain.nameTag}'
          '${o.hasTrim ? cutSuffix(o.trimStart!, o.trimEnd!) : ''}';
      final r = await convertAudio(
        src,
        name,
        o.audioFormat,
        inArgs: [
          if (o.hasTrim) ...[
            '-ss',
            o.trimStart!.toStringAsFixed(3),
            '-t',
            (o.trimEnd! - o.trimStart!).toStringAsFixed(3),
          ],
        ],
        outArgs: localAudioArgs(
          srcExt: extensionOf(src),
          format: o.audioFormat,
          gain: o.gain,
          metadata: {
            'title': info.title,
            'artist': info.uploader,
            'date': info.uploadDate ?? '',
            'purl': info.url,
          },
        ),
        token: token,
      );
      if (token.cancelled) throw CancelledException();
      onProgress(const DownloadProgress(percent: 1, stage: '저장 중…'));
      return r;
    } on CancelledException {
      rethrow;
    } catch (_) {
      if (token.cancelled) throw CancelledException();
      return null;
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

  /// 앱 자체 업데이트(설치 파일을 받아 실행)를 지원하는지. 테스트용 가짜 백엔드는 false.
  bool get canSelfUpdate => false;

  /// Android: 이 기기의 주 ABI(`arm64-v8a` 등). 어떤 APK 를 받을지 고르는 데 쓴다.
  Future<String?> deviceAbi() async => null;

  /// 받은 설치 파일을 실행한다. 돌려주는 문구가 있으면 사용자에게 그대로 보여 준다.
  /// Windows 는 설치 프로그램을 띄우고 이 앱을 끝낸다. Android 는 시스템 설치 화면을 연다.
  Future<String?> installUpdate(String path) async =>
      throw UnimplementedError();

  /// 다른 앱(유튜브 앱 등)에서 공유로 넘어온 텍스트(Android만).
  Future<String?> takeInitialSharedText() async => null;
  void Function(String text)? onSharedText;
}

Backend createBackend() =>
    Platform.isAndroid ? AndroidBackend() : DesktopBackend();
