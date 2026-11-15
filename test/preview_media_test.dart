import 'package:flutter_test/flutter_test.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/util/preview_media.dart';

Map<String, dynamic> _sb(
  String id,
  int w,
  int h,
  int cols,
  int rows,
  List<double> durations, {
  double fps = 0.2,
}) =>
    {
      'format_id': id,
      'protocol': 'mhtml',
      'width': w,
      'height': h,
      'columns': cols,
      'rows': rows,
      'fps': fps,
      'fragments': [
        for (var i = 0; i < durations.length; i++) {'url': 'https://i/$id/$i.jpg', 'duration': durations[i]},
      ],
    };

Map<String, dynamic> _audio(String id, String codec, num abr, {String protocol = 'https'}) => {
      'format_id': id,
      'protocol': protocol,
      'vcodec': 'none',
      'acodec': codec,
      'abr': abr,
      'url': 'https://a/$id',
    };

void main() {
  group('Storyboard', () {
    // 실제 영상(10분 35초)의 sb1: 5x5 칸, 124초짜리 5장 + 14.9초짜리 1장(3칸)
    final formats = [
      _sb('sb3', 48, 27, 10, 10, [635]),
      _sb('sb1', 160, 90, 5, 5, [124, 124, 124, 124, 124, 14.9], fps: 0.2015748),
    ];

    test('가로 320 이상 중 가장 작은 것을 고르고, 없으면 가장 큰 것', () {
      final all = [
        ...formats,
        _sb('sb0', 320, 180, 3, 3, [44.6, 44.6], fps: 0.2015748),
        _sb('sbX', 640, 360, 2, 2, [20, 20]),
      ];
      expect(Storyboard.fromFormats(all, 635)!.frameWidth, 320);
      final b = Storyboard.fromFormats(formats, 635)!; // 160 이 가장 큰 것
      expect(b.frameWidth, 160);
      expect(b.columns, 5);
      expect(b.totalFrames, 128);
      expect(b.urls.length, 6);
    });

    test('시각 → 그림 한 장과 칸 위치', () {
      final b = Storyboard.fromFormats(formats, 635)!;
      final f0 = b.frameAt(0);
      expect((f0.url, f0.column, f0.row), ('https://i/sb1/0.jpg', 0, 0));
      // 5초 간격이니 약 12초 → 2번째 장면(칸 2, 줄 0)
      final f12 = b.frameAt(12);
      expect((f12.column, f12.row), (2, 0));
      // 30초 → 6번째 장면(칸 1, 줄 1)
      final f30 = b.frameAt(30);
      expect((f30.column, f30.row), (1, 1));
      // 25장이 넘으면 다음 그림으로
      final f130 = b.frameAt(130);
      expect(f130.url, 'https://i/sb1/1.jpg');
    });

    test('마지막 그림은 잘려 있다(3칸 1줄)', () {
      final b = Storyboard.fromFormats(formats, 635)!;
      final last = b.frameAt(634);
      expect(last.url, 'https://i/sb1/5.jpg');
      expect((last.columns, last.rows), (3, 1));
      expect((last.column, last.row), (2, 0));
    });

    test('영상 길이를 넘는 시각도 안전하게 마지막 장면', () {
      final b = Storyboard.fromFormats(formats, 635)!;
      expect(b.frameAt(99999).url, 'https://i/sb1/5.jpg');
      expect(b.frameAt(-5).column, 0);
    });

    test('없거나 이상하면 null', () {
      expect(Storyboard.fromFormats(null, 10), isNull);
      expect(Storyboard.fromFormats([], 10), isNull);
      expect(Storyboard.fromFormats([_audio('140', 'mp4a.40.2', 128)], 10), isNull);
    });
  });

  group('pickPreviewAudioUrl', () {
    test('AAC(mp4a.40.2)를 먼저, -drc/조각 목록은 제외', () {
      final url = pickPreviewAudioUrl([
        _audio('251', 'opus', 128),
        _audio('140-drc', 'mp4a.40.2', 128),
        _audio('233', 'mp4a.40.2', 100, protocol: 'm3u8_native'),
        _audio('140', 'mp4a.40.2', 129),
        _audio('139', 'mp4a.40.5', 48),
      ]);
      expect(url, 'https://a/140');
    });

    test('AAC 가 없으면 다른 소리 전용 스트림', () {
      expect(pickPreviewAudioUrl([_audio('251', 'opus', 128), _audio('250', 'opus', 65)]), 'https://a/250');
    });

    test('소리 전용 스트림이 없으면 null', () {
      expect(pickPreviewAudioUrl([]), isNull);
      expect(pickPreviewAudioUrl(null), isNull);
      expect(
        pickPreviewAudioUrl([
          {'format_id': '18', 'protocol': 'https', 'vcodec': 'avc1', 'acodec': 'mp4a.40.2', 'url': 'https://a/18'},
        ]),
        isNull,
      );
    });
  });

  test('MediaInfo.fromJson 이 둘 다 채운다', () {
    final info = MediaInfo.fromJson({
      'id': 'x',
      'title': 't',
      'duration': 635,
      'formats': [
        _sb('sb1', 160, 90, 5, 5, [124, 124, 124, 124, 124, 14.9], fps: 0.2015748),
        _audio('140', 'mp4a.40.2', 129),
      ],
    }, 'https://youtu.be/x');
    expect(info.storyboard, isNotNull);
    expect(info.previewAudioUrl, 'https://a/140');
  });
}
