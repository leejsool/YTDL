import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../util/names.dart';
import 'backend.dart';
import 'gain_args.dart';
import 'video_args.dart';
import 'ytdlp_args.dart';

class AndroidBackend extends Backend {
  AndroidBackend() {
    _method.setMethodCallHandler((call) async {
      if (call.method == 'sharedText') {
        final t = call.arguments as String?;
        if (t != null) onSharedText?.call(t);
      }
    });
    _events.receiveBroadcastStream().listen((e) {
      final m = Map<String, dynamic>.from(e as Map);
      _listeners[m['id']]?.call(m['line'] as String? ?? '');
    });
  }

  static const _method = MethodChannel('ytdl/native');
  static const _events = EventChannel('ytdl/progress');
  final Map<String, void Function(String line)> _listeners = {};
  // 앱을 다시 켜도 임시 폴더 이름이 겹치지 않게 시각에서 시작한다.
  int _seq = DateTime.now().millisecondsSinceEpoch;

  String _folder = 'YTDL';

  @override
  String get folderName => _folder;

  @override
  bool get canRenameFolder => true;

  @override
  String get saveLocationLabel => '음원 → Music/$_folder · 영상 → Movies/$_folder';

  /// 폴더 이름으로 쓸 수 없는 글자를 걷어낸다. 비면 기본값.
  static String cleanFolderName(String name) {
    final t = name.replaceAll(RegExp(r'[\\/:*?"<>|]'), '').trim();
    return t.isEmpty ? 'YTDL' : t;
  }

  @override
  Future<void> setFolderName(String name) async {
    _folder = cleanFolderName(name);
    await _method.invokeMethod<bool>('setFolder', {'name': _folder});
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('set_folder', _folder);
    } catch (_) {}
  }

  @override
  Future<void> prepare(SetupCallback onStatus) async {
    onStatus('다운로드 엔진을 준비하는 중…', null);
    await _method.invokeMethod('init');
    cleanAudioCache();
    try {
      final prefs = await SharedPreferences.getInstance();
      _folder = cleanFolderName(prefs.getString('set_folder') ?? 'YTDL');
      await _method.invokeMethod<bool>('setFolder', {'name': _folder});
    } catch (_) {}
    // 유튜브가 자주 바뀌어서 내장 yt-dlp 가 낡으면 403 등으로 다운로드가 막힌다. 하루에 한 번 최신으로 맞춘다.
    // (앱을 새로 설치하면 내장 버전으로 돌아가므로, 그때는 첫 실행에 바로 업데이트된다.)
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt('lastUpdateCheck') ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - last > const Duration(hours: 24).inMilliseconds) {
        onStatus('다운로드 엔진을 최신으로 업데이트하는 중…', null);
        await _method.invokeMethod<String>('update');
        await prefs.setInt('lastUpdateCheck', now);
      }
    } catch (_) {
      // 인터넷이 없거나 업데이트에 실패해도 기존 엔진으로 계속 쓴다.
    }
  }

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final json = await _method.invokeMethod<String>('getInfo', {'url': url});
    // yt-dlp가 경고 줄을 섞어 내보낼 수 있어 JSON 객체 줄만 골라낸다.
    final line = (json ?? '')
        .split('\n')
        .lastWhere(
          (l) => l.trimLeft().startsWith('{'),
          orElse: () => throw Exception('영상 정보를 읽지 못했습니다.'),
        );
    return MediaInfo.fromJson(
      jsonDecode(line) as Map<String, dynamic>,
      url,
      raw: line,
    );
  }

  @override
  Future<PlaylistInfo> fetchPlaylist(String url, {int limit = 200}) async {
    final json = await _method.invokeMethod<String>('getInfo', {
      'url': url,
      'playlist': true,
      'limit': limit,
    });
    final line = (json ?? '')
        .split('\n')
        .lastWhere(
          (l) => l.trimLeft().startsWith('{'),
          orElse: () => throw Exception('재생목록을 읽지 못했습니다.'),
        );
    return PlaylistInfo.fromJson(await decodeJsonOffThread(line), url);
  }

  @override
  Future<double> measureGain(
    String source,
    CancelToken token, {
    bool remote = false,
    double? startSec,
    double? endSec,
  }) async {
    if (token.cancelled) throw CancelledException();
    // 구간 미리듣기용으로 이미 받아 둔 소리가 있으면 그걸로 잰다(다시 받지 않는다).
    final cached = remote ? await cachedFullAudio(source) : null;
    if (cached != null) {
      return measureGain(cached, token, startSec: startSec, endSec: endSec);
    }
    final id = 'gain${_seq++}';
    token.onCancel = () {
      unawaited(
        _method
            .invokeMethod<void>('cancel', {'id': id})
            .catchError((Object _) {}),
      );
    };
    try {
      final log = await _method.invokeMethod<String>('measureGain', {
        'id': id,
        'source': source,
        'downloadArgs': remote
            ? buildAudioProbeArgs(startSec: startSec, endSec: endSec)
            : null,
        'measureArgs': gainMeasureArgs(
          'YTDL_AUDIO_INPUT',
          startSec: remote ? null : startSec,
          endSec: remote ? null : endSec,
        ),
      });
      if (token.cancelled) throw CancelledException();
      return gainFromMeasurement(log ?? '');
    } on PlatformException catch (e) {
      if (token.cancelled) throw CancelledException();
      throw Exception(e.message ?? '음량을 분석하지 못했습니다.');
    } finally {
      token.onCancel = null;
    }
  }

  @override
  Future<DownloadResult> download(
    String url,
    DownloadOptions options,
    void Function(DownloadProgress) onProgress,
    CancelToken token,
  ) async {
    // 음원은 받아 둔 소리 스트림으로 폰 안에서 바로 만든다(안 되면 아래 yt-dlp 로).
    final local = await downloadAudioLocally(url, options, onProgress, token);
    if (local != null) return local;
    // 조회 때 받아 둔 정보를 쓰는 빠른 길이 실패하면(링크 만료 등) 주소로 처음부터 한 번 더 시도한다.
    if (options.infoJson != null) {
      try {
        return await _downloadOnce(url, options, onProgress, token);
      } on CancelledException {
        rethrow;
      } catch (_) {
        if (token.cancelled) throw CancelledException();
      }
    }
    return _downloadOnce(url, options, onProgress, token, useInfo: false);
  }

  Future<DownloadResult> _downloadOnce(
    String url,
    DownloadOptions options,
    void Function(DownloadProgress) onProgress,
    CancelToken token, {
    bool useInfo = true,
  }) async {
    final id = 'dl${_seq++}';
    final parser = ProgressParser();
    _listeners[id] = (line) {
      final p = parser.parse(line);
      if (p != null) onProgress(p);
    };
    token.onCancel = () => _method.invokeMethod('cancel', {'id': id});
    try {
      final r = await _method.invokeMapMethod<String, String>('download', {
        'id': id,
        'url': url,
        'args': buildDownloadArgs(options),
        'audio': options.kind == MediaKind.audio,
        if (useInfo && options.infoJson != null) 'infoJson': options.infoJson,
        // 음량 조절이 있으면 받은 뒤 내장 ffmpeg 로 다시 인코딩(없으면 null).
        'gainArgs': options.kind == MediaKind.audio
            ? gainEncodeArgs(options.gain, options.audioFormat)
            : null,
        // 영상 구간: 전체를 받은 뒤 폰 안에서 복사로 자른다(구간만 받기보다 훨씬 빠르다).
        if (options.cutsVideoLocally) ...{
          'cutStart': options.trimStart!.toDouble(),
          'cutLength': (options.trimEnd! - options.trimStart!).toDouble(),
          'cutArgs': videoTrimArgs(reencode: false, outExt: 'mp4'),
        },
      });
      return DownloadResult(
        location: r?['location'] ?? '',
        filePath: r?['path'],
      );
    } on PlatformException catch (e) {
      if (token.cancelled) throw CancelledException();
      throw Exception(e.message ?? '다운로드에 실패했습니다.');
    } finally {
      _listeners.remove(id);
    }
  }

  @override
  Future<DownloadResult> trimAudio(
    String srcPath,
    double startSec,
    double endSec,
    String outBaseName, {
    AudioGain gain = const AudioGain.none(),
  }) async {
    try {
      final ext = extensionOf(srcPath);
      final r = await _method.invokeMapMethod<String, String>('trimAudio', {
        'src': srcPath,
        'startMs': (startSec * 1000).round(),
        'endMs': (endSec * 1000).round(),
        'outName': '$outBaseName.$ext',
        // null 이면 그대로 복사(-c copy), 있으면 음량 조절하며 다시 인코딩.
        'encodeArgs': gainEncodeArgs(gain, ext),
      });
      return DownloadResult(
        location: r?['location'] ?? '',
        filePath: r?['path'],
      );
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '자르기에 실패했습니다.');
    }
  }

  @override
  Future<DownloadResult> convertAudio(
    String srcPath,
    String outBaseName,
    String ext, {
    List<String> inArgs = const [],
    List<String> outArgs = const [],
    CancelToken? token,
  }) async {
    try {
      final r = await _method.invokeMapMethod<String, String>('convertAudio', {
        'src': srcPath,
        'outName': '$outBaseName.$ext',
        'inArgs': inArgs,
        'outArgs': outArgs,
      });
      return DownloadResult(
        location: r?['location'] ?? '',
        filePath: r?['path'],
      );
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '음원을 만들지 못했습니다.');
    }
  }

  @override
  Future<DownloadResult> trimVideo(
    String srcPath,
    double startSec,
    double endSec,
    String outBaseName, {
    bool reencode = false,
  }) async {
    try {
      final ext = videoTrimExtension(extensionOf(srcPath), reencode: reencode);
      final r = await _method.invokeMapMethod<String, String>('trimVideo', {
        'src': srcPath,
        'startMs': (startSec * 1000).round(),
        'endMs': (endSec * 1000).round(),
        'outName': '$outBaseName.$ext',
        'args': videoTrimArgs(reencode: reencode, outExt: ext),
      });
      return DownloadResult(location: r?['location'] ?? '', filePath: r?['path']);
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '영상 자르기에 실패했습니다.');
    }
  }

  @override
  Future<String> previewDownload(String url, List<String> args) async {
    try {
      final path = await _method.invokeMethod<String>('previewSegment', {
        'id': 'pv${_seq++}',
        'url': url,
        'args': args,
      });
      return path ?? (throw Exception('미리듣기 소리를 받지 못했습니다.'));
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '미리듣기 소리를 받지 못했습니다.');
    }
  }

  @override
  Future<String> previewGain(
    String srcPath,
    AudioGain gain, {
    double? startSec,
    double? endSec,
    String ext = 'm4a',
  }) async {
    final range = startSec != null && endSec != null;
    if (!range && !gain.isActive && srcPath.toLowerCase().endsWith('.$ext')) {
      return srcPath;
    }
    try {
      final path = await _method.invokeMethod<String>('previewGain', {
        'src': srcPath,
        'outName':
            '${previewFileKey(srcPath)}_${previewGainTag(gain)}'
            '${range ? '_${startSec.round()}_${endSec.round()}' : ''}.$ext',
        'startSec': startSec,
        'endSec': endSec,
        'args': previewEncodeArgs(gain, ext),
      });
      return path ?? (throw Exception('미리듣기 파일을 만들지 못했습니다.'));
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '미리듣기 파일을 만들지 못했습니다.');
    }
  }

  @override
  Future<String> updateEngine() async {
    final r = await _method.invokeMethod<String>('update');
    return switch (r) {
      'DONE' => '최신 버전으로 업데이트했습니다',
      'ALREADY_UP_TO_DATE' => '이미 최신 버전입니다',
      _ => r ?? '완료',
    };
  }

  @override
  Future<String?> takeInitialSharedText() =>
      _method.invokeMethod<String>('getSharedText');
}
