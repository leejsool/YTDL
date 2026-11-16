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
      // 음량(LUFS)만 재면 되므로 ebur128 을 쓴다. loudnorm 으로 재면 같은 값이 나오지만
      // 안에서 192kHz 로 바꿔 계산해서 10배 넘게 느리다(10분 음원: 약 60초 vs 5초).
      // 5.1채널 소리는 그대로 재면 훨씬 느려서 스테레오로 내려서 잰다(잰 값은 같다).
      '-af',
      'aformat=channel_layouts=stereo,ebur128=framelog=quiet',
      '-f',
      'null',
      '-',
    ];

/// ffmpeg 측정 로그에서 전체 음량을 읽어 목표까지 필요한 dB 를 돌려준다.
/// ebur128 요약(`I: -18.7 LUFS`)을 읽고, 예전 loudnorm 출력(`"input_i"`)도 알아듣는다.
double gainFromMeasurement(String log) {
  double? loudness;
  final summary = RegExp(r'\bI:\s+(-?\d+(?:\.\d+)?) LUFS').allMatches(log);
  if (summary.isNotEmpty) {
    loudness = double.tryParse(summary.last.group(1)!);
    // 소리가 없으면 ebur128 은 바닥값(-70)을 낸다.
    if (loudness != null && loudness <= -69.9) loudness = null;
  } else {
    final match = RegExp(r'"input_i"\s*:\s*"([^"]+)"').firstMatch(log);
    loudness = double.tryParse(match?.group(1) ?? '');
  }
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

/// 받아 둔 소리 스트림([srcExt]: m4a / webm …)을 [format] (mp3 | m4a | opus) 파일로 만드는 ffmpeg 출력 인자.
/// 코덱이 이미 같고 음량도 그대로면 다시 인코딩하지 않고 담기만 한다(거의 즉시, 음질 손실 없음).
/// 입력 쪽(-ss/-t/-i)과 출력 경로는 호출하는 쪽이 붙인다.
List<String> localAudioArgs({
  required String srcExt,
  required String format,
  AudioGain gain = const AudioGain.none(),
  Map<String, String> metadata = const {},
}) {
  final filter = gainFilter(gain);
  final src = srcExt.toLowerCase();
  final copy =
      filter == null &&
      ((format == 'm4a' && (src == 'm4a' || src == 'mp4')) ||
          (format == 'opus' && (src == 'webm' || src == 'opus')));
  return [
    '-map',
    '0:a:0',
    '-vn',
    if (copy) ...['-c:a', 'copy'] else ...[
      if (filter != null) ...['-af', filter],
      ..._codecFor(format),
    ],
    if (format == 'm4a') ...['-movflags', '+faststart'],
    for (final e in metadata.entries)
      if (e.value.isNotEmpty) ...['-metadata', '${e.key}=${e.value}'],
  ];
}

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
