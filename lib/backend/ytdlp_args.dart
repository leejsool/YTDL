/// Windows(yt-dlp.exe)와 Android(youtubedl-android) 양쪽이 똑같이 쓰는
/// yt-dlp 명령행 인자 생성기. 저장 폴더(-P)와 URL은 각 플랫폼 쪽에서 붙인다.
library;

import '../models.dart';
import '../util/names.dart';

/// yt-dlp가 최종 파일 경로를 알려줄 때 쓰는 접두어.
const String fileMarker = 'YTDL_FILE:';

List<String> buildDownloadArgs(DownloadOptions o) {
  var name = '%(title).100s';
  if (o.hasTrim) {
    name += cutSuffix(o.trimStart!, o.trimEnd!);
  }

  final args = <String>[
    '--no-playlist',
    '--newline',
    '--progress',
    '--no-colors',
    '--windows-filenames',
    '--no-mtime',
    '--embed-metadata',
    '-o',
    '$name.%(ext)s',
    '--print',
    'after_move:$fileMarker%(filepath)s',
  ];

  if (o.kind == MediaKind.audio) {
    args.addAll([
      '-f', 'bestaudio/best',
      '-x',
      '--audio-format', o.audioFormat,
      '--audio-quality', '0',
    ]);
  } else {
    final h = o.maxHeight;
    // 해상도를 먼저 맞추고, 같은 해상도면 H.264 + AAC(m4a)를 우선해서
    // 어느 플레이어에서든 재생되는 mp4로 합친다.
    final sort = h == null ? 'res,vcodec:h264,acodec:m4a' : 'res:$h,vcodec:h264,acodec:m4a';
    args.addAll([
      '-f', 'bv*+ba/b',
      '-S', sort,
      '--merge-output-format', 'mp4',
    ]);
  }

  if (o.hasTrim) {
    args.addAll([
      '--download-sections', '*${o.trimStart}-${o.trimEnd}',
      '--force-keyframes-at-cuts',
    ]);
  }
  return args;
}

/// yt-dlp 출력 한 줄을 진행 상태로 해석한다.
class ProgressParser {
  static final RegExp _pct = RegExp(r'\[download\]\s+(\d+(?:\.\d+)?)%');

  String? filePath;

  DownloadProgress? parse(String line) {
    if (line.startsWith(fileMarker)) {
      filePath = line.substring(fileMarker.length).trim();
      return const DownloadProgress(percent: 1, stage: '저장 중…');
    }
    final m = _pct.firstMatch(line);
    if (m != null) {
      return DownloadProgress(
        percent: (double.parse(m.group(1)!) / 100).clamp(0.0, 1.0),
        stage: '다운로드 중',
      );
    }
    if (line.contains('[ExtractAudio]') ||
        line.contains('[Merger]') ||
        line.contains('[VideoConvertor]') ||
        line.contains('[FixupM4a]') ||
        line.contains('[Metadata]')) {
      return const DownloadProgress(stage: '변환 중…');
    }
    return null;
  }
}
