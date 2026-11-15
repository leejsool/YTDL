/// 영상 자르기용 ffmpeg 인자. Windows(ffmpeg.exe)와 Android(내장 libffmpeg.so)가 똑같이 쓴다.
/// 입력·출력 경로와 -ss/-t 는 호출하는 쪽이 붙인다.
library;

/// 정확하게(다시 인코딩)는 항상 mp4, 빠르게(복사)는 원본 형식 그대로.
String videoTrimExtension(String srcExt, {required bool reencode}) {
  if (reencode) return 'mp4';
  return srcExt.isEmpty ? 'mp4' : srcExt.toLowerCase();
}

bool _supportsFaststart(String ext) =>
    const {'mp4', 'm4v', 'mov'}.contains(ext.toLowerCase());

/// - 복사: 화면과 소리를 다시 만들지 않아 빠르고 화질 손실이 없다. 대신 시작 지점이 앞쪽 키프레임으로 당겨질 수 있다.
/// - 다시 인코딩: 지정한 시각에서 정확히 시작한다. 시간이 오래 걸리고 파일이 약간 달라진다(화질은 거의 같게 CRF 20).
List<String> videoTrimArgs({required bool reencode, required String outExt}) =>
    [
      '-map',
      '0:v:0?',
      '-map',
      '0:a?',
      if (reencode) ...[
        '-c:v',
        'libx264',
        '-preset',
        'veryfast',
        '-crf',
        '20',
        '-pix_fmt',
        'yuv420p',
        '-c:a',
        'aac',
        '-b:a',
        '192k',
      ] else ...[
        '-c',
        'copy',
        '-avoid_negative_ts',
        'make_zero',
      ],
      if (_supportsFaststart(outExt)) ...['-movflags', '+faststart'],
    ];
