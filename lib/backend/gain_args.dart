/// 음량 조절용 ffmpeg 인자. Windows(ffmpeg.exe)와 Android(내장 libffmpeg.so)가 똑같이 쓴다.
library;

import '../models.dart';

/// ffmpeg `-af` 에 넣을 필터. 조절이 없으면 null.
String? gainFilter(AudioGain g) {
  if (!g.isActive) return null;
  if (g.mode == GainMode.auto) {
    // 유튜브가 맞추는 기준(-14 LUFS)으로. 한 번에 처리(single pass)라 빠르다.
    return 'loudnorm=I=-14:TP=-1.5:LRA=11';
  }
  final v = 'volume=${g.db.toStringAsFixed(1)}dB';
  // 키울 때는 최대치를 넘는 부분이 찌그러지지(클리핑) 않게 리미터를 붙인다.
  // level=0 : 리미터가 전체 음량을 다시 낮추지 못하게 한다.
  return g.db > 0 ? '$v,alimiter=limit=0.97:level=0' : v;
}

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
bool _keepsCover(String ext) => const {'mp3', 'm4a', 'flac'}.contains(ext.toLowerCase());

/// `-c copy` 대신 쓸 "다시 인코딩 + 음량 조절" 인자. 입력/출력 경로는 호출하는 쪽이 붙인다.
/// 조절이 없으면 null(= `-c copy` 를 쓴다).
List<String>? gainEncodeArgs(AudioGain g, String ext) {
  final f = gainFilter(g);
  if (f == null) return null;
  return [
    '-map', '0:a',
    if (_keepsCover(ext)) ...['-map', '0:v?', '-c:v', 'copy'],
    '-af', f,
    ..._codecFor(ext),
  ];
}
