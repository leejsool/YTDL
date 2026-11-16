import 'package:flutter_test/flutter_test.dart';
import 'package:ytdl/backend/gain_args.dart';
import 'package:ytdl/backend/ytdlp_args.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/util/names.dart';
import 'package:ytdl/util/preview_media.dart';

Map<String, dynamic> _audio(String id, String codec, num abr, {num? lang}) => {
  'format_id': id,
  'protocol': 'https',
  'vcodec': 'none',
  'acodec': codec,
  'abr': abr,
  'url': 'https://a/$id',
  'language_preference': ?lang,
};

MediaInfo _info(int duration) => MediaInfo(
  id: 'x',
  title: 't',
  uploader: 'u',
  url: 'https://www.youtube.com/watch?v=aaaaaaaaaaa',
  durationSeconds: duration,
);

void main() {
  group('형식별 소리 스트림 고르기', () {
    final formats = [
      _audio('139', 'mp4a.40.5', 48),
      _audio('140', 'mp4a.40.2', 129),
      _audio('140-drc', 'mp4a.40.2', 200),
      _audio('250', 'opus', 65),
      _audio('251', 'opus', 128),
      _audio('251-1', 'opus', 160, lang: -5), // 더빙
    ];

    test('같은 코덱 중 비트레이트가 가장 높은 것, -drc 와 더빙은 뒤로', () {
      expect(pickAudioUrlByCodec(formats, 'mp4a'), 'https://a/140');
      expect(pickAudioUrlByCodec(formats, 'opus'), 'https://a/251');
      expect(pickAudioUrlByCodec(formats, 'flac'), isNull);
      expect(pickAudioUrlByCodec(null, 'opus'), isNull);
    });

    test('MediaInfo 가 저장 형식에 맞는 주소를 준다', () {
      final info = MediaInfo.fromJson({'id': 'x', 'title': 't', 'duration': 60, 'formats': formats}, 'u');
      expect(info.audioUrlFor('m4a'), 'https://a/140');
      expect(info.audioUrlFor('opus'), 'https://a/251');
      expect(info.audioUrlFor('mp3'), info.previewAudioUrl);
    });
  });

  group('받아 둔 소리로 파일 만들기 인자', () {
    test('코덱이 같고 음량 그대로면 다시 인코딩하지 않는다', () {
      expect(localAudioArgs(srcExt: 'm4a', format: 'm4a'), containsAllInOrder(['-c:a', 'copy']));
      expect(localAudioArgs(srcExt: 'webm', format: 'opus'), containsAllInOrder(['-c:a', 'copy']));
    });

    test('코덱이 다르거나 음량을 바꾸면 인코딩한다', () {
      expect(localAudioArgs(srcExt: 'webm', format: 'mp3'), containsAllInOrder(['-c:a', 'libmp3lame']));
      expect(localAudioArgs(srcExt: 'webm', format: 'm4a'), containsAllInOrder(['-c:a', 'aac']));
      final boosted = localAudioArgs(srcExt: 'm4a', format: 'm4a', gain: const AudioGain.manual(6));
      expect(boosted, isNot(contains('copy')));
      expect(boosted, containsAllInOrder(['-af', 'volume=6.0dB,alimiter=limit=0.97:level=0']));
    });

    test('태그는 빈 값을 빼고 붙인다', () {
      final args = localAudioArgs(srcExt: 'webm', format: 'mp3', metadata: {'title': 'A=B', 'date': ''});
      expect(args, containsAllInOrder(['-metadata', 'title=A=B']));
      expect(args.join(' '), isNot(contains('date=')));
    });
  });

  group('yt-dlp 인자', () {
    String fmt(String f) {
      final a = buildDownloadArgs(DownloadOptions(kind: MediaKind.audio, audioFormat: f));
      return a[a.indexOf('-f') + 1];
    }

    test('목표 형식과 같은 코덱의 스트림을 먼저 고른다', () {
      expect(fmt('m4a'), startsWith('bestaudio[ext=m4a]/'));
      expect(fmt('opus'), startsWith('bestaudio[acodec=opus]/'));
      expect(fmt('mp3'), 'bestaudio/best');
    });

    test('영상 구간: 짧은 영상은 전체를 받아 자르고, 긴 영상의 짧은 구간은 구간만 받는다', () {
      DownloadOptions o(int total, int s, int e) =>
          const DownloadOptions(kind: MediaKind.video, trimStart: 0, trimEnd: 0).withInfo(_info(total)).copyTrim(s, e);
      expect(o(600, 60, 120).cutsVideoLocally, isTrue);
      expect(buildDownloadArgs(o(600, 60, 120)), isNot(contains('--download-sections')));
      expect(o(7200, 60, 120).cutsVideoLocally, isFalse);
      expect(buildDownloadArgs(o(7200, 60, 120)), contains('--download-sections'));
      expect(o(7200, 0, 1800).cutsVideoLocally, isTrue);
      // 조회 정보가 없으면 예전 방식.
      expect(
        const DownloadOptions(kind: MediaKind.video, trimStart: 1, trimEnd: 5).cutsVideoLocally,
        isFalse,
      );
      // 음원은 해당 없음.
      expect(
        const DownloadOptions(kind: MediaKind.audio, trimStart: 1, trimEnd: 5).withInfo(_info(60)).cutsVideoLocally,
        isFalse,
      );
    });
  });

  test('음량 측정: ebur128 요약에서 전체 음량을 읽는다', () {
    const log = '''
[Parsed_ebur128_0 @ 000] Summary:

  Integrated loudness:
    I:         -18.7 LUFS
    Threshold: -29.2 LUFS

  Loudness range:
    LRA:        9.9 LU
''';
    expect(gainFromMeasurement(log), closeTo(gainTargetLufs + 18.7, .001));
    expect(() => gainFromMeasurement(log.replaceFirst('-18.7', '-70.0')), throwsException);
    expect(() => gainFromMeasurement('아무 것도 없음'), throwsException);
  });

  test('제목을 yt-dlp 와 같은 방식의 파일 이름으로', () {
    expect(fileNameFromTitle('A/B: C? "D" <E> | F*'), 'A⧸B： C？ ＂D＂ ＜E＞ ｜ F＊');
    expect(fileNameFromTitle('  끝에 점...  '), '끝에 점');
    expect(fileNameFromTitle('a\nb'), 'a b');
    expect(fileNameFromTitle('x' * 150).length, 100);
    expect(fileNameFromTitle(''), '_');
    expect(stableHash('abc'), stableHash('abc'));
    expect(stableHash('abc'), isNot(stableHash('abd')));
  });
}

extension on DownloadOptions {
  DownloadOptions copyTrim(int s, int e) => DownloadOptions(
    kind: kind,
    audioFormat: audioFormat,
    maxHeight: maxHeight,
    trimStart: s,
    trimEnd: e,
    gain: gain,
    infoJson: infoJson,
    info: info,
  );
}
