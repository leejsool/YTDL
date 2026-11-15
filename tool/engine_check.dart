// 앱이 쓰는 yt-dlp 인자(buildDownloadArgs)가 실제로 동작하는지 확인하는 개발용 스크립트.
//
//   dart run tool/engine_check.dart <도구폴더> <출력폴더> <영상URL>
//
// <도구폴더> 에는 yt-dlp.exe, ffmpeg.exe, ffprobe.exe, deno.exe 가 있어야 한다.
import 'dart:convert';
import 'dart:io';

import 'package:ytdl/backend/ytdlp_args.dart';
import 'package:ytdl/models.dart';

Future<void> main(List<String> argv) async {
  if (argv.length < 3) {
    stderr.writeln('usage: dart run tool/engine_check.dart <toolsDir> <outDir> <url>');
    exit(64);
  }
  final tools = argv[0];
  final out = argv[1];
  final url = argv[2];
  Directory(out).createSync(recursive: true);

  final common = [
    '--ffmpeg-location', tools,
    '--js-runtimes', 'deno:$tools\\deno.exe',
    '--encoding', 'utf-8',
    '--no-warnings',
  ];
  const env = {'PYTHONIOENCODING': 'utf-8', 'PYTHONUTF8': '1'};

  // 1) 정보 조회
  final info = await Process.run(
    '$tools\\yt-dlp.exe',
    [...common, '--no-playlist', '--dump-single-json', url],
    environment: env,
    stdoutEncoding: utf8,
    stderrEncoding: utf8,
  );
  if (info.exitCode != 0) {
    stderr.writeln('정보 조회 실패:\n${info.stderr}');
    exit(1);
  }
  final j = jsonDecode(info.stdout as String) as Map<String, dynamic>;
  final dur = (j['duration'] as num).round();
  stdout.writeln('[정보] ${j['title']} / ${j['uploader']} / ${dur}s');

  final cases = <String, DownloadOptions>{
    '음원 MP3 전체': const DownloadOptions(kind: MediaKind.audio),
    '음원 MP3 구간(5~12초)':
        const DownloadOptions(kind: MediaKind.audio, trimStart: 5, trimEnd: 12),
    '음원 M4A 구간(2~8초)': const DownloadOptions(
        kind: MediaKind.audio, audioFormat: 'm4a', trimStart: 2, trimEnd: 8),
    '영상 360p MP4': const DownloadOptions(kind: MediaKind.video, maxHeight: 360),
    '영상 360p MP4 구간(3~9초)': const DownloadOptions(
        kind: MediaKind.video, maxHeight: 360, trimStart: 3, trimEnd: 9),
  };

  var failed = 0;
  for (final e in cases.entries) {
    final parser = ProgressParser();
    final err = StringBuffer();
    final proc = await Process.start(
      '$tools\\yt-dlp.exe',
      [...common, '-P', out, ...buildDownloadArgs(e.value), url],
      environment: env,
    );
    final o = proc.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .forEach(parser.parse);
    final er = proc.stderr.transform(utf8.decoder).forEach(err.write);
    final code = await proc.exitCode;
    await o;
    await er;

    final path = parser.filePath;
    if (code != 0 || path == null || !File(path).existsSync()) {
      failed++;
      stdout.writeln('[실패] ${e.key} (exit $code, path=$path)\n$err');
      continue;
    }
    final probe = await Process.run('$tools\\ffprobe.exe', [
      '-v', 'error',
      '-show_entries', 'format=duration:stream=codec_type,codec_name',
      '-of', 'csv=p=0',
      path,
    ]);
    final fileName = path.split('\\').last;
    stdout.writeln('[성공] ${e.key}\n   파일: $fileName (${File(path).lengthSync()} bytes)\n'
        '   ffprobe: ${(probe.stdout as String).trim().replaceAll('\n', ' | ')}');
  }
  exit(failed == 0 ? 0 : 1);
}
