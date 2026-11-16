/// Windows(yt-dlp.exe)와 Android(youtubedl-android) 양쪽이 똑같이 쓰는
/// yt-dlp 명령행 인자 생성기. 저장 폴더(-P)와 URL은 각 플랫폼 쪽에서 붙인다.
library;

import '../models.dart';
import '../util/names.dart';

/// yt-dlp가 최종 파일 경로를 알려줄 때 쓰는 접두어.
const String fileMarker = 'YTDL_FILE:';

/// Android 쪽이 "받은 뒤 음량 조절 시작"을 알릴 때 보내는 줄.
const String gainMarker = 'YTDL_GAIN';

/// Android 쪽이 "받은 영상에서 구간 자르기 시작"을 알릴 때 보내는 줄.
const String cutMarker = 'YTDL_CUT';

List<String> buildAudioProbeArgs({double? startSec, double? endSec}) => [
  '--no-playlist',
  '--no-progress',
  '--no-warnings',
  '-f',
  'bestaudio/best',
  '-o',
  'probe.%(ext)s',
  '--print',
  'after_move:$fileMarker%(filepath)s',
  if (startSec != null && endSec != null) ...[
    '--download-sections',
    '*$startSec-$endSec',
  ],
];

/// 미리듣기용: [startSec]~[endSec] 부분의 소리만 받는다(어느 폰에서나 재생되는 m4a 우선).
List<String> buildPreviewSegmentArgs(double startSec, double endSec) => [
  '--no-playlist',
  '--no-progress',
  '--no-warnings',
  '--force-overwrites',
  '-f',
  'bestaudio[ext=m4a]/bestaudio/best',
  '-o',
  'preview.%(ext)s',
  '--print',
  'after_move:$fileMarker%(filepath)s',
  '--download-sections',
  '*$startSec-$endSec',
];

/// 미리듣기용: 구간 없이 소리 전체를 받는다(구간만 받기가 안 될 때의 대비책).
List<String> buildPreviewFullArgs() => [
  '--no-playlist',
  '--no-progress',
  '--no-warnings',
  '--force-overwrites',
  '-f',
  'bestaudio[ext=m4a]/bestaudio/best',
  '-o',
  'preview.%(ext)s',
  '--print',
  'after_move:$fileMarker%(filepath)s',
];

List<String> buildDownloadArgs(DownloadOptions o) {
  var name = '%(title).100s';
  // 음량 조절은 yt-dlp 가 아니라 받은 뒤 ffmpeg 로 따로 한다(yt-dlp 는 이미 목표 형식이면
  // 변환 단계를 건너뛰어 필터가 적용되지 않는다). 파일 이름 표시만 여기서 붙인다.
  if (o.kind == MediaKind.audio) name += o.gain.nameTag;
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
      '-f',
      // 목표 형식과 같은 코덱의 스트림이 있으면 그걸 받는다. 그러면 변환이 "담기만"으로 끝나
      // 다시 인코딩하는 시간(10분 음원에 수십 초)과 음질 손실이 없다.
      switch (o.audioFormat) {
        'm4a' => 'bestaudio[ext=m4a]/bestaudio/best',
        'opus' => 'bestaudio[acodec=opus]/bestaudio/best',
        _ => 'bestaudio/best',
      },
      '-x',
      '--audio-format',
      o.audioFormat,
      '--audio-quality',
      '0',
    ]);
  } else {
    final h = o.maxHeight;
    // 해상도를 먼저 맞추고, 같은 해상도면 H.264 + AAC(m4a)를 우선해서
    // 어느 플레이어에서든 재생되는 mp4로 합친다.
    final sort = h == null
        ? 'res,vcodec:h264,acodec:m4a'
        : 'res:$h,vcodec:h264,acodec:m4a';
    args.addAll(['-f', 'bv*+ba/b', '-S', sort, '--merge-output-format', 'mp4']);
  }

  // 영상 구간을 기기 안에서 자르기로 했으면 여기서는 전체를 받는다(이름에는 구간 표시가 그대로 붙는다).
  if (o.hasTrim && !o.cutsVideoLocally) {
    args.addAll([
      '--download-sections',
      '*${o.trimStart}-${o.trimEnd}',
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
    if (line.startsWith(gainMarker)) {
      return const DownloadProgress(percent: 1, stage: '음량 조절 중…');
    }
    if (line.startsWith(cutMarker)) {
      return const DownloadProgress(percent: 1, stage: '구간 자르는 중…');
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
