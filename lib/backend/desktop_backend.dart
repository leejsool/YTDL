import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models.dart';
import '../util/names.dart';
import 'backend.dart';
import 'gain_args.dart';
import 'video_args.dart';
import 'ytdlp_args.dart';

class _YtdlpRun {
  const _YtdlpRun(this.code, this.errLines, this.path);
  final int code;
  final List<String> errLines;
  final String? path;
}

/// Windows용 엔진. %LOCALAPPDATA%\YTDL\bin 에 yt-dlp / ffmpeg / deno 를 두고 직접 실행한다.
///  - yt-dlp.exe : 다운로드 본체
///  - ffmpeg.exe : 변환·병합·구간 자르기
///  - deno.exe   : 유튜브 서명 해독용 JS 런타임(yt-dlp 가 요구)
class DesktopBackend extends Backend {
  // 폴더형(yt-dlp_win.zip)을 쓴다. 단일 exe 는 실행할 때마다 압축을 풀어 매번 1초 넘게 더 걸린다.
  static const _ytdlpZipUrl =
      'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_win.zip';
  static const _ytdlpOneFileUrl =
      'https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp.exe';
  static const _ffmpegUrl =
      'https://github.com/yt-dlp/FFmpeg-Builds/releases/latest/download/ffmpeg-master-latest-win64-gpl.zip';
  static const _denoUrl =
      'https://github.com/denoland/deno/releases/latest/download/deno-x86_64-pc-windows-msvc.zip';

  late final String _binDir;
  // prepare() 가 저장해 둔 값으로 바꾸기 전에도(예: 옵션 탭이 먼저 그려질 때) 읽을 수 있게 기본값을 둔다.
  String _saveDir = [
    Platform.environment['USERPROFILE'] ?? 'C:',
    'Downloads',
    'YTDL',
  ].join(Platform.pathSeparator);
  SharedPreferences? _prefs;

  String get _ytdlpDir => '$_binDir\\ytdlp';
  String get _ytdlpFast => '$_ytdlpDir\\yt-dlp.exe';
  String get _ytdlpOneFile => '$_binDir\\yt-dlp.exe';

  /// 폴더형이 있으면 그걸, 없으면(내려받기 실패 등) 예전 단일 exe 를 쓴다.
  String get _ytdlp =>
      File(_ytdlpFast).existsSync() ? _ytdlpFast : _ytdlpOneFile;
  String get _ffmpeg => '$_binDir\\ffmpeg.exe';
  String get _deno => '$_binDir\\deno.exe';

  static const _env = {'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'};

  List<String> get _common => [
    '--ffmpeg-location',
    _binDir,
    '--js-runtimes',
    'deno:$_deno',
    '--encoding',
    'utf-8',
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
    final base =
        Platform.environment['LOCALAPPDATA'] ?? '$home\\AppData\\Local';
    _binDir = '$base\\YTDL\\bin';
    Directory(_binDir).createSync(recursive: true);

    if (!File(_ytdlpFast).existsSync()) {
      try {
        await _fetchYtdlpDir(onStatus);
        // 폴더형이 자리 잡았으니 예전 단일 exe 는 지운다.
        try {
          if (File(_ytdlpOneFile).existsSync()) File(_ytdlpOneFile).deleteSync();
        } catch (_) {}
      } catch (_) {
        // 폴더형을 못 받아도 단일 exe 가 있으면 그걸로 계속, 아무것도 없으면 단일 exe 를 받는다.
        if (!File(_ytdlpOneFile).existsSync()) {
          await _fetch(_ytdlpOneFileUrl, _ytdlpOneFile, 'yt-dlp 내려받는 중', onStatus);
        }
      }
    }
    if (!File(_ffmpeg).existsSync()) {
      await _fetchZip(
        _ffmpegUrl,
        ['ffmpeg.exe', 'ffprobe.exe'],
        'ffmpeg 내려받는 중 (처음 한 번, 약 100MB)',
        onStatus,
      );
    }
    if (!File(_deno).existsSync()) {
      await _fetchZip(_denoUrl, ['deno.exe'], 'JS 런타임 내려받는 중', onStatus);
    }

    // 유튜브는 자주 바뀌므로 하루에 한 번 yt-dlp 를 최신으로 맞춘다.
    final last = _prefs!.getInt('lastUpdateCheck') ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - last > const Duration(days: 1).inMilliseconds) {
      // 화면은 바로 열고 업데이트 확인은 뒤에서 한다. 그 사이 yt-dlp 를 쓰는 작업은 끝날 때까지 기다린다
      // (실행 중인 yt-dlp 를 교체하면 안 되므로, [_engineReady]).
      _updating = () async {
        try {
          await Process.run(_ytdlp, [
            '-U',
          ], environment: _env).timeout(const Duration(seconds: 60));
          await _prefs!.setInt('lastUpdateCheck', now);
        } catch (_) {
          // 오프라인 등으로 실패해도 기존 엔진으로 계속 진행.
        }
      }();
    }
  }

  /// 백그라운드 업데이트 확인이 돌고 있으면 그게 끝날 때까지 기다린다.
  Future<void> _updating = Future.value();
  Future<void> _engineReady() => _updating;

  Future<void> _fetch(
    String url,
    String dest,
    String label,
    SetupCallback onStatus,
  ) async {
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

  /// yt-dlp 폴더형을 받아 `bin\ytdlp` 에 푼다. 다 풀린 뒤에 제자리로 옮겨서 중간에 끊겨도 반쪽짜리가 남지 않는다.
  Future<void> _fetchYtdlpDir(SetupCallback onStatus) async {
    final zip = '$_binDir\\_ytdlp.zip';
    final tmp = Directory('$_binDir\\_ytdlp_new');
    try {
      await _fetch(_ytdlpZipUrl, zip, 'yt-dlp 내려받는 중', onStatus);
      onStatus('압축 푸는 중…', null);
      if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      tmp.createSync();
      final r = await Process.run('tar.exe', ['-xf', zip, '-C', tmp.path]);
      if (r.exitCode != 0 || !File('${tmp.path}\\yt-dlp.exe').existsSync()) {
        throw Exception('압축 해제 실패: ${r.stderr}');
      }
      final dest = Directory(_ytdlpDir);
      if (dest.existsSync()) dest.deleteSync(recursive: true);
      tmp.renameSync(dest.path);
    } finally {
      try {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        if (File(zip).existsSync()) File(zip).deleteSync();
      } catch (_) {}
    }
  }

  Future<void> _fetchZip(
    String url,
    List<String> wanted,
    String label,
    SetupCallback onStatus,
  ) async {
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
    await _engineReady();
    final r = await Process.run(
      _ytdlp,
      [
        ..._common,
        '--no-playlist',
        // HLS 목록은 쓰지 않는다(받아 오는 데 0.5초쯤 걸리고 JSON 만 커진다).
        '--extractor-args',
        'youtube:skip=hls',
        '--dump-single-json',
        url,
      ],
      environment: _env,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0)
      throw Exception(_summarize((r.stderr as String).split('\n')));
    final raw = r.stdout as String;
    return MediaInfo.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
      url,
      raw: raw,
    );
  }

  @override
  Future<double> measureGain(
    String source,
    CancelToken token, {
    bool remote = false,
    double? startSec,
    double? endSec,
  }) async {
    // 구간 미리듣기용으로 이미 받아 둔 소리가 있으면 그걸로 잰다(yt-dlp 를 다시 돌려 받을 필요가 없다).
    final cached = remote ? await cachedFullAudio(source) : null;
    if (cached != null) {
      return measureGain(
        cached,
        token,
        startSec: startSec,
        endSec: endSec,
      );
    }
    final work = remote
        ? await Directory.systemTemp.createTemp('ytdl_gain_')
        : null;
    try {
      var input = source;
      if (work != null) {
        final output = await _runGainProbe(_ytdlp, [
          ..._common,
          '-P',
          work.path,
          ...buildAudioProbeArgs(startSec: startSec, endSec: endSec),
          '--',
          source,
        ], token);
        final parser = ProgressParser();
        for (final line in const LineSplitter().convert(output)) {
          parser.parse(line);
        }
        input = parser.filePath ?? (throw Exception('분석할 음원을 받지 못했습니다.'));
      }
      final log = await _runGainProbe(
        _ffmpeg,
        gainMeasureArgs(
          input,
          startSec: remote ? null : startSec,
          endSec: remote ? null : endSec,
        ),
        token,
      );
      return gainFromMeasurement(log);
    } finally {
      if (work != null) await work.delete(recursive: true);
    }
  }

  Future<String> _runGainProbe(
    String executable,
    List<String> args,
    CancelToken token,
  ) async {
    await _engineReady();
    if (token.cancelled) throw CancelledException();
    final process = await Process.start(executable, args, environment: _env);
    void stop() {
      unawaited(
        Process.run('taskkill', [
          '/T',
          '/F',
          '/PID',
          '${process.pid}',
        ]).then<void>((_) {}, onError: (Object _) {}),
      );
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
      final output = (await logs.timeout(
        const Duration(seconds: 8),
        onTimeout: () => ['', ''],
      )).join('\n');
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

    // 조회 때 받아 둔 정보가 있으면 yt-dlp 가 분석을 다시 하지 않고 바로 받는다(약 3초 절약).
    // 링크가 만료됐거나 어떤 이유로든 실패하면 주소로 처음부터 다시 시도한다.
    _YtdlpRun? run;
    final infoJson = options.infoJson;
    if (infoJson != null) {
      final file = File(
        '${Directory.systemTemp.path}\\ytdl_info_${DateTime.now().microsecondsSinceEpoch}.json',
      );
      try {
        await file.writeAsString(infoJson);
        run = await _runDownload(
          ['--load-info-json', file.path],
          options,
          onProgress,
          token,
        );
      } on FileSystemException {
        run = null; // 임시 파일을 못 만들면 그냥 주소로 받는다.
      } finally {
        try {
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
      if (token.cancelled) throw CancelledException();
      if (run != null && run.code != 0) run = null;
    }
    run ??= await _runDownload([url], options, onProgress, token);

    if (token.cancelled) throw CancelledException();
    if (run.code != 0) throw Exception(_summarize(run.errLines));
    final path = run.path;

    // 음량 조절: 받은 파일을 같은 형식으로 다시 인코딩해서 바꿔치기한다.
    if (options.kind == MediaKind.audio &&
        options.gain.isActive &&
        path != null) {
      onProgress(const DownloadProgress(stage: '음량 조절 중…'));
      try {
        await _applyGain(path, options.gain, token);
      } on CancelledException {
        rethrow;
      } catch (e) {
        throw Exception(
          '음량 조절에 실패했어요. 받은 파일은 음량 조절 없이 저장돼 있어요: $path\n'
          '${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    }
    return DownloadResult(location: path ?? _saveDir, filePath: path);
  }

  /// yt-dlp 를 한 번 실행해 받는다. [target] 은 주소(`[url]`) 또는 `['--load-info-json', 파일]`.
  Future<_YtdlpRun> _runDownload(
    List<String> target,
    DownloadOptions options,
    void Function(DownloadProgress) onProgress,
    CancelToken token,
  ) async {
    final first = await _runDownloadOnce(target, options, onProgress, token);
    // 구간 받기(--download-sections)에서 ffmpeg 가 10번에 한 번쯤 이상한 종료 코드로 죽는다
    // (같은 명령을 다시 하면 대부분 성공). 그런 경우만 한 번 더 시도한다.
    if (first.code != 0 &&
        !token.cancelled &&
        first.errLines.any((l) => l.contains('ffmpeg exited with code'))) {
      return _runDownloadOnce(target, options, onProgress, token);
    }
    return first;
  }

  Future<_YtdlpRun> _runDownloadOnce(
    List<String> target,
    DownloadOptions options,
    void Function(DownloadProgress) onProgress,
    CancelToken token,
  ) async {
    await _engineReady();
    if (token.cancelled) throw CancelledException();
    final proc = await Process.start(_ytdlp, [
      ..._common,
      '-P',
      _saveDir,
      ...buildDownloadArgs(options),
      ...target,
    ], environment: _env);
    // ffmpeg 자식 프로세스까지 함께 종료.
    token.onCancel = () =>
        Process.run('taskkill', ['/T', '/F', '/PID', '${proc.pid}']);

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
    await Future.wait([
      out,
      err,
    ]).timeout(const Duration(seconds: 5), onTimeout: () => const []);
    return _YtdlpRun(code, errLines, parser.filePath);
  }

  /// [path] 파일의 음량을 바꿔 같은 이름으로 다시 저장한다. 실패하면 원래 파일은 그대로 둔다.
  Future<void> _applyGain(
    String path,
    AudioGain gain,
    CancelToken token,
  ) async {
    final ext = extensionOf(path);
    final encode = gainEncodeArgs(gain, ext);
    if (encode == null) return;
    final tmp = '${path.substring(0, path.length - ext.length - 1)}.gain.$ext';
    try {
      final proc = await Process.start(_ffmpeg, [
        '-nostdin',
        '-y',
        '-loglevel',
        'error',
        '-i',
        path,
        '-map_metadata',
        '0',
        ...encode,
        tmp,
      ]);
      token.onCancel = () =>
          Process.run('taskkill', ['/T', '/F', '/PID', '${proc.pid}']);
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

  Future<Directory> _previewDir() async {
    final d = Directory('${Directory.systemTemp.path}\\ytdl_preview');
    await d.create(recursive: true);
    // 오래된 미리듣기 파일 정리(10분 지난 것)
    for (final e in d.listSync()) {
      try {
        if (DateTime.now().difference(e.statSync().modified).inMinutes > 10) {
          e.deleteSync(recursive: true);
        }
      } catch (_) {}
    }
    return d;
  }

  @override
  Future<String> previewDownload(String url, List<String> args) async {
    final root = await _previewDir();
    final dir = await root.createTemp('seg_');
    final output = await _runGainProbe(_ytdlp, [
      ..._common,
      '-P',
      dir.path,
      ...args,
      '--',
      url,
    ], CancelToken());
    final parser = ProgressParser();
    for (final line in const LineSplitter().convert(output)) {
      parser.parse(line);
    }
    final path = parser.filePath;
    if (path == null || !File(path).existsSync()) {
      throw Exception('미리듣기 소리를 받지 못했습니다.');
    }
    return path;
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
    final root = await _previewDir();
    final out =
        '${root.path}\\${previewFileKey(srcPath)}_${previewGainTag(gain)}'
        '${range ? '_${startSec.round()}_${endSec.round()}' : ''}.$ext';
    if (File(out).existsSync() && File(out).lengthSync() > 0) return out;
    await _runGainProbe(_ffmpeg, [
      '-nostdin',
      '-y',
      '-loglevel',
      'error',
      if (range) ...[
        '-ss',
        startSec.toStringAsFixed(3),
        '-t',
        (endSec - startSec).toStringAsFixed(3),
      ],
      '-i',
      srcPath,
      ...previewEncodeArgs(gain, ext),
      out,
    ], CancelToken());
    if (!File(out).existsSync() || File(out).lengthSync() == 0) {
      throw Exception('미리듣기 파일이 비어 있습니다.');
    }
    return out;
  }

  @override
  Future<DownloadResult> trimVideo(
    String srcPath,
    double startSec,
    double endSec,
    String outBaseName, {
    bool reencode = false,
  }) async {
    final src = File(srcPath);
    if (!src.existsSync()) throw Exception('원본 파일을 찾을 수 없습니다: $srcPath');
    final ext = videoTrimExtension(extensionOf(srcPath), reencode: reencode);
    final dir = src.parent.path;
    final sep = Platform.pathSeparator;
    var out = '$dir$sep$outBaseName.$ext';
    for (var i = 2; File(out).existsSync(); i++) {
      out = '$dir$sep$outBaseName ($i).$ext';
    }
    final r = await Process.run(
      _ffmpeg,
      [
        '-nostdin', '-y', '-loglevel', 'error',
        '-ss', startSec.toStringAsFixed(3),
        '-i', srcPath,
        '-t', (endSec - startSec).toStringAsFixed(3),
        '-map_metadata', '0',
        ...videoTrimArgs(reencode: reencode, outExt: ext),
        out,
      ],
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    if (r.exitCode != 0 || !File(out).existsSync()) {
      throw Exception(_summarize(('${r.stderr}').split(RegExp(r'\r?\n'))));
    }
    return DownloadResult(location: out, filePath: out);
  }

  @override
  Future<String> updateEngine() async {
    await _engineReady();
    final r = await Process.run(
      _ytdlp,
      ['-U'],
      environment: _env,
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    await _prefs?.setInt(
      'lastUpdateCheck',
      DateTime.now().millisecondsSinceEpoch,
    );
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
