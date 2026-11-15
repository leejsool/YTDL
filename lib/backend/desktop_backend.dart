import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../util/names.dart';
import 'backend.dart';
import 'gain_args.dart';
import 'ytdlp_args.dart';

/// Windows용 엔진. %LOCALAPPDATA%\YTDL\bin 에 yt-dlp / ffmpeg / deno 를 두고 직접 실행한다.
///  - yt-dlp.exe : 다운로드 본체
///  - ffmpeg.exe : 변환·병합·구간 자르기
///  - deno.exe   : 유튜브 서명 해독용 JS 런타임(yt-dlp 가 요구)
class DesktopBackend extends Backend {
  static const _ytdlpUrl =
      'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';
  static const _ffmpegUrl =
      'https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip';
  static const _denoUrl =
      'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip';

  late final String _binDir;
  late String _saveDir;
  SharedPreferences? _prefs;

  String get _ytdlp => '$_binDir\\yt-dlp.exe';
  String get _ffmpeg => '$_binDir\\ffmpeg.exe';
  String get _deno => '$_binDir\\deno.exe';

  static const _env = {'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'};

  List<String> get _common => [
        '--ffmpeg-location', _binDir,
        '--js-runtimes', 'deno:$_deno',
        '--encoding', 'utf-8',
        '--no-warnings',
      ];

  @override
  String get saveLocationLabel => _saveDir;

  @override
  bool get canChooseFolder => true;

  @override
  Future<void> chooseFolder() async {
    final dir = await FilePicker.getDirectoryPath(dialogTitle: '저장 폴더 선택');
    if (dir != null) {
      _saveDir = dir;
      await _prefs?.setString('saveDir', dir);
    }
  }

  @override
  bool get canReveal => true;

  @override
  Future<void> reveal(DownloadResult result) async {
    final f = result.filePath;
    if (f != null && File(f).existsSync()) {
      await Process.run('explorer.exe', ['/select,', f]);
    } else {
      await Process.run('explorer.exe', [_saveDir]);
    }
  }

  // ---------------------------------------------------------------- 준비
  @override
  Future<void> prepare(SetupCallback onStatus) async {
    _prefs = await SharedPreferences.getInstance();
    final home = Platform.environment['USERPROFILE'] ?? 'C:\\';
    _saveDir = _prefs!.getString('saveDir') ?? '$home\\Downloads\\YTDL';
    final base = Platform.environment['LOCALAPPDATA'] ?? '$home\\AppData\\Local';
    _binDir = '$base\\YTDL\\bin';
    Directory(_binDir).createSync(recursive: true);

    if (!File(_ytdlp).existsSync()) {
      await _fetch(_ytdlpUrl, _ytdlp, 'yt-dlp 내려받는 중', onStatus);
    }
    if (!File(_ffmpeg).existsSync()) {
      await _fetchZip(_ffmpegUrl, ['ffmpeg.exe', 'ffprobe.exe'],
          'ffmpeg 내려받는 중 (처음 한 번, 약 100MB)', onStatus);
    }
    if (!File(_deno).existsSync()) {
      await _fetchZip(_denoUrl, ['deno.exe'], 'JS 런타임 내려받는 중', onStatus);
    }

    // 유튜브는 자주 바뀌므로 하루에 한 번 yt-dlp 를 최신으로 맞춘다.
    final last = _prefs!.getInt('lastUpdateCheck') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last > const Duration(days: 1).inMilliseconds) {
      onStatus('다운로드 엔진 업데이트 확인 중…', null);
      try {
        await Process.run(_ytdlp, ['-U'], environment: _env)
            .timeout(const Duration(seconds: 60));
        await _prefs!.setInt('lastUpdateCheck', now);
      } catch (_) {
        // 오프라인 등으로 실패해도 기존 엔진으로 계속 진행.
      }
    }
  }

  Future<void> _fetch(
      String url, String dest, String label, SetupCallback onStatus) async {
    onStatus(label, null);
    final client = HttpClient()..userAgent = 'ytdl-app';
    try {
      final res = await (await client.getUrl(Uri.parse(url))).close();
      if (res.statusCode != 200) {
        throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(url));
      }
      final total = res.contentLength;
      final part = File('$dest.part');
      final sink = part.openWrite();
      var got = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        onStatus(label, total > 0 ? got / total : null);
      }
      await sink.close();
      if (File(dest).existsSync()) File(dest).deleteSync();
      await part.rename(dest);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _fetchZip(String url, List<String> wanted, String label,
      SetupCallback onStatus) async {
    final zip = '$_binDir\\_download.zip';
    final tmp = Directory('$_binDir\\_extract');
    await _fetch(url, zip, label, onStatus);
    onStatus('압축 푸는 중…', null);
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
    tmp.createSync();
    // Windows 10/11 에 기본 포함된 tar.exe 가 zip 도 풀 수 있다.
    final r = await Process.run('tar.exe', ['-xf', zip, '-C', tmp.path]);
    if (r.exitCode != 0) {
      throw Exception('압축 해제 실패: ${r.stderr}');
    }
    for (final entity in tmp.listSync(recursive: true)) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (wanted.contains(name)) {
        entity.copySync('$_binDir\\$name');
      }
    }
    tmp.deleteSync(recursive: true);
    File(zip).deleteSync();
  }

  // ---------------------------------------------------------------- 정보
  @override
  Future<MediaInfo> fetchInfo(String url) async {
    final r = await Process.run(
      _ytdlp,
      [..._common, '--no-playlist', '--dump-single-json', url],
      environment: _env,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0) throw Exception(_summarize((r.stderr as String).split('\n')));
    return MediaInfo.fromJson(jsonDecode(r.stdout as String) as Map<String, dynamic>, url);
  }

  @override
  Future<double> measureGain(
    String source,
    CancelToken token, {
    bool remote = false,
    double? startSec,
    double? endSec,
  }) async {
    final work = remote ? await Directory.systemTemp.createTemp('ytdl_gain_') : null;
    try {
      var input = source;
      if (work != null) {
        final output = await _runGainProbe(_ytdlp, [
          ..._common, '-P', work.path,
          ...buildAudioProbeArgs(startSec: startSec, endSec: endSec), '--', source,
        ], token);
        final parser = ProgressParser();
        for (final line in const LineSplitter().convert(output)) {
          parser.parse(line);
        }
        input = parser.filePath ?? (throw Exception('분석할 음원을 받지 못했습니다.'));
      }
      final log = await _runGainProbe(_ffmpeg, gainMeasureArgs(
        input, startSec: remote ? null : startSec, endSec: remote ? null : endSec,
      ), token);
      return gainFromMeasurement(log);
    } finally {
      if (work != null) await work.delete(recursive: true);
    }
  }

  Future<String> _runGainProbe(String executable, List<String> args, CancelToken token) async {
    if (token.cancelled) throw CancelledException();
    final process = await Process.start(executable, args, environment: _env);
    void stop() {
      unawaited(Process.run('taskkill', ['/T', '/F', '/PID', '${process.pid}']).then<void>((_) {}, onError: (Object _) {}));
    }
    token.onCancel = stop;
    if (token.cancelled) stop();
    try {
      const decoder = Utf8Decoder(allowMalformed: true);
      final logs = Future.wait([
        process.stdout.transform(decoder).join(),
        process.stderr.transform(decoder).join(),
      ]);
      final code = await process.exitCode;
      final output = (await logs.timeout(const Duration(seconds: 8), onTimeout: () => ['', ''])).join('\n');
      if (token.cancelled) throw CancelledException();
      if (code != 0) throw Exception(_summarize(output.split('\n')));
      return output;
    } finally {
      token.onCancel = null;
    }
  }

  // ---------------------------------------------------------------- 다운로드
  @override
  Future<DownloadResult> download(
    String url,
    DownloadOptions options,
    void Function(DownloadProgress) onProgress,
    CancelToken token,
  ) async {
    Directory(_saveDir).createSync(recursive: true);
    final proc = await Process.start(
      _ytdlp,
      [..._common, '-P', _saveDir, ...buildDownloadArgs(options), url],
      environment: _env,
    );
    // ffmpeg 자식 프로세스까지 함께 종료.
    token.onCancel =
        () => Process.run('taskkill', ['/T', '/F', '/PID', '${proc.pid}']);

    final parser = ProgressParser();
    final errLines = <String>[];
    final out = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach((line) {
      final p = parser.parse(line);
      if (p != null) onProgress(p);
    });
    final err = proc.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(errLines.add);

    final code = await proc.exitCode;
    // yt-dlp 가 끝났는데 그 자식 프로세스(deno/ffmpeg)가 출력 파이프를 계속 붙잡고 있으면
    // 스트림이 닫히지 않아 영원히 "다운로드 중"에 머물 수 있다. 남은 출력은 보통 즉시 도착하므로
    // 잠깐만 기다리고 넘어간다.
    await Future.wait([out, err]).timeout(const Duration(seconds: 5), onTimeout: () => const []);

    if (token.cancelled) throw CancelledException();
    if (code != 0) throw Exception(_summarize(errLines));
    final path = parser.filePath;

    // 음량 조절: 받은 파일을 같은 형식으로 다시 인코딩해서 바꿔치기한다.
    if (options.kind == MediaKind.audio && options.gain.isActive && path != null) {
      onProgress(const DownloadProgress(stage: '음량 조절 중…'));
      try {
        await _applyGain(path, options.gain, token);
      } on CancelledException {
        rethrow;
      } catch (e) {
        throw Exception('음량 조절에 실패했어요. 받은 파일은 음량 조절 없이 저장돼 있어요: $path\n'
            '${e.toString().replaceFirst('Exception: ', '')}');
      }
    }
    return DownloadResult(location: path ?? _saveDir, filePath: path);
  }

  /// [path] 파일의 음량을 바꿔 같은 이름으로 다시 저장한다. 실패하면 원래 파일은 그대로 둔다.
  Future<void> _applyGain(String path, AudioGain gain, CancelToken token) async {
    final ext = extensionOf(path);
    final encode = gainEncodeArgs(gain, ext);
    if (encode == null) return;
    final tmp = '${path.substring(0, path.length - ext.length - 1)}.gain.$ext';
    try {
      final proc = await Process.start(_ffmpeg, [
        '-nostdin', '-y', '-loglevel', 'error',
        '-i', path,
        '-map_metadata', '0',
        ...encode,
        tmp,
      ]);
      token.onCancel = () => Process.run('taskkill', ['/T', '/F', '/PID', '${proc.pid}']);
      final err = proc.stderr.transform(utf8.decoder).join();
      unawaited(proc.stdout.drain<void>());
      final code = await proc.exitCode;
      final log = await err;
      if (token.cancelled) throw CancelledException();
      if (code != 0 || !File(tmp).existsSync() || File(tmp).lengthSync() == 0) {
        throw Exception(_summarize(log.split('\n')));
      }
      File(path).deleteSync();
      File(tmp).renameSync(path);
    } finally {
      final f = File(tmp);
      if (f.existsSync()) f.deleteSync();
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
    final src = File(srcPath);
    if (!src.existsSync()) throw Exception('원본 파일을 찾을 수 없습니다: $srcPath');
    final ext = extensionOf(srcPath);
    final dir = src.parent.path;

    // 같은 이름이 이미 있으면 덮어쓰지 않고 " (2)", " (3)" 을 붙인다.
    var out = '$dir\\$outBaseName.$ext';
    for (var i = 2; File(out).existsSync(); i++) {
      out = '$dir\\$outBaseName ($i).$ext';
    }

    final r = await Process.run(
      _ffmpeg,
      [
        '-nostdin', '-y', '-loglevel', 'error',
        '-i', srcPath,
        '-ss', startSec.toStringAsFixed(3),
        '-t', (endSec - startSec).toStringAsFixed(3),
        '-map_metadata', '0',
        // 음량을 바꿀 때만 다시 인코딩하고, 아니면 그대로 복사(음질 손실 없음).
        ...(gainEncodeArgs(gain, ext) ?? const ['-c', 'copy']),
        out,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0 || !File(out).existsSync()) {
      throw Exception(_summarize(('${r.stderr}').split('\n')));
    }
    return DownloadResult(location: out, filePath: out);
  }

  @override
  Future<String> updateEngine() async {
    final r = await Process.run(_ytdlp, ['-U'],
        environment: _env, stdoutEncoding: utf8, stderrEncoding: utf8);
    await _prefs?.setInt('lastUpdateCheck', DateTime.now().millisecondsSinceEpoch);
    final text = '${r.stdout}'.trim();
    return text.isEmpty ? '완료' : text.split('\n').last;
  }

  String _summarize(List<String> lines) {
    final errors = lines.where((l) => l.contains('ERROR')).toList();
    final pick = errors.isNotEmpty
        ? errors.last
        : lines.where((l) => l.trim().isNotEmpty).lastOrNull ?? '알 수 없는 오류';
    return pick.replaceFirst(RegExp(r'^ERROR:\s*'), '').trim();
  }
}
