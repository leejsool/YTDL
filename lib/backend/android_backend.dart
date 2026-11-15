import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../models.dart';
import '../util/names.dart';
import 'backend.dart';
import 'gain_args.dart';
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
  int _seq = 0;

  @override
  String get saveLocationLabel => '음원 → Music/YTDL · 영상 → Movies/YTDL';

  @override
  Future<void> prepare(SetupCallback onStatus) async {
    onStatus('다운로드 엔진을 준비하는 중…', null);
    await _method.invokeMethod('init');
  }

  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final json = await _method.invokeMethod<String>('getInfo', {'url': url});
    // yt-dlp가 경고 줄을 섞어 내보낼 수 있어 JSON 객체 줄만 골라낸다.
    final line = (json ?? '').split('\n').lastWhere(
          (l) => l.trimLeft().startsWith('{'),
          orElse: () => throw Exception('영상 정보를 읽지 못했습니다.'),
        );
    return MediaInfo.fromJson(jsonDecode(line) as Map<String, dynamic>, url);
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
    final id = 'gain${_seq++}';
    token.onCancel = () {
      unawaited(_method.invokeMethod<void>('cancel', {'id': id}).catchError((Object _) {}));
    };
    try {
      final log = await _method.invokeMethod<String>('measureGain', {
        'id': id,
        'source': source,
        'downloadArgs': remote ? buildAudioProbeArgs(startSec: startSec, endSec: endSec) : null,
        'measureArgs': gainMeasureArgs('YTDL_AUDIO_INPUT',
          startSec: remote ? null : startSec, endSec: remote ? null : endSec),
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
        // 음량 조절이 있으면 받은 뒤 내장 ffmpeg 로 다시 인코딩(없으면 null).
        'gainArgs': options.kind == MediaKind.audio
            ? gainEncodeArgs(options.gain, options.audioFormat)
            : null,
      });
      return DownloadResult(location: r?['location'] ?? '', filePath: r?['path']);
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
      return DownloadResult(location: r?['location'] ?? '', filePath: r?['path']);
    } on PlatformException catch (e) {
      throw Exception(e.message ?? '자르기에 실패했습니다.');
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
