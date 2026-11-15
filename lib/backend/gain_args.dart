/// 음량 조절용 ffmpeg 인자. Windows(ffmpeg.exe)와 Android(내장 libffmpeg.so)가 똑같이 쓴다.
library;

import '../models.dart';

/// 자동 음량 조절의 목표(LUFS). 기본은 유튜브 기준 -14. 옵션 탭에서 바꾸면 AppSettings 가 이 값을 갱신한다.
int gainTargetLufs = -14;

List<String> gainMeasureArgs(String path, {double? startSec, double? endSec}) =>
    [
      '-nostdin',
      '-hide_banner',
      '-nostats',
      if (startSec != null && endSec != null) ...[
        '-ss',
        startSec.toStringAsFixed(3),
        '-t',
        (endSec - startSec).toStringAsFixed(3),
      ],
      '-i',
      path,
      '-map',
      '0:a:0',
      '-vn',
      '-sn',
      '-dn',
      '-af',
      'loudnorm=I=$gainTargetLufs:TP=-1.5:LRA=11:print_format=json',
      '-f',
      'null',
      '-',
    ];

double gainFromMeasurement(String log) {
  final match = RegExp(r'"input_i"\s*:\s*"([^"]+)"').firstMatch(log);
  final loudness = double.tryParse(match?.group(1) ?? '');
  if (loudness == null || !loudness.isFinite) {
    throw Exception('선택한 구간에서 음량을 측정할 수 없습니다.');
  }
  return gainTargetLufs - loudness;
}

/// ffmpeg `-af` 에 넣을 필터. 조절이 없으면 null.
String? gainFilter(AudioGain g) {
  if (!g.isActive) return null;
  if (g.mode == GainMode.auto) {
    // 유튜브가 맞추는 기준(-14 LUFS)으로. 한 번에 처리(single pass)라 빠르다.
    return 'loudnorm=I=$gainTargetLufs:TP=-1.5:LRA=11';
  }
  final v = 'volume=${g.db.toStringAsFixed(1)}dB';
  // 키울 때는 최대치를 넘는 부분이 찌그러지지(클리핑) 않게 리미터를 붙인다.
  // level=0 : 리미터가 전체 음량을 다시 낮추지 못하게 한다.
  return g.db > 0 ? '$v,alimiter=limit=0.97:level=0' : v;
}

/// 미리듣기용 재생 파일 인자(m4a). 음량 조절이 있으면 적용해서 다시 인코딩한다.
List<String> previewEncodeArgs(AudioGain g, [String ext = 'm4a']) =>
    gainEncodeArgs(g, ext) ??
    (ext == 'wav'
        ? const ['-vn', '-c:a', 'pcm_s16le']
        : const ['-vn', '-c:a', 'aac', '-b:a', '192k']);

/// 미리듣기 결과 파일 이름 꼬리표(음량마다 다른 파일이 되게).
String previewGainTag(AudioGain g) => !g.isActive
    ? 'plain'
    : g.mode == GainMode.auto
    ? 'auto'
    : 'g${g.db.round()}';

/// 확장자에 맞는 인코더. 원본과 같은 형식으로 다시 만들되 음질은 넉넉하게 잡는다.
List<String> _codecFor(String ext) => switch (ext.toLowerCase()) {
  'mp3' => ['-c:a', 'libmp3lame', '-q:a', '0'],
  'm4a' || 'aac' || 'mp4' => ['-c:a', 'aac', '-b:a', '256k'],
  'opus' => ['-c:a', 'libopus', '-b:a', '192k'],
  'ogg' || 'oga' => ['-c:a', 'libvorbis', '-q:a', '6'],
  'flac' => ['-c:a', 'flac'],
  'wav' => ['-c:a', 'pcm_s16le'],
  'wma' => ['-c:a', 'wmav2', '-b:a', '192k'],
  _ => const [],
};

/// 앨범 그림(표지)을 담을 수 있는 형식은 그림도 그대로 가져간다.
bool _keepsCover(String ext) =>
    const {'mp3', 'm4a', 'flac'}.contains(ext.toLowerCase());

/// `-c copy` 대신 쓸 "다시 인코딩 + 음량 조절" 인자. 입력/출력 경로는 호출하는 쪽이 붙인다.
/// 조절이 없으면 null(= `-c copy` 를 쓴다).
List<String>? gainEncodeArgs(AudioGain g, String ext) {
  final f = gainFilter(g);
  if (f == null) return null;
  return [
    '-map',
    '0:a',
    if (_keepsCover(ext)) ...['-map', '0:v?', '-c:v', 'copy'],
    '-af',
    f,
    ..._codecFor(ext),
  ];
}
