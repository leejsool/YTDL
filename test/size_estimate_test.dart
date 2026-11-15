import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/util/size_estimate.dart';

MediaInfo load(String name) {
  final j = jsonDecode(File('test/fixtures/${name}_info.json').readAsStringSync())
      as Map<String, dynamic>;
  return MediaInfo.fromJson(j, 'https://youtu.be/${j['id']}');
}

void main() {
  // 실제 yt-dlp 가 --simulate 로 알려 준 합계 용량(바이트): Big Buck Bunny
  //   1080p: 299+258 = 288,387,264   720p: 298+258 = 181,292,478
  //   480p : 135+258 =  58,974,755   360p: 18      =  28,526,904
  group('예상 용량이 yt-dlp 의 실제 선택과 일치', () {
    final bbb = load('bbb');
    const actual = {1080: 288387264, 720: 181292478, 480: 58974755, 360: 28526904};
    actual.forEach((h, bytes) {
      test('${h}p', () {
        final est = estimateVideoBytes(bbb, h)!;
        expect((est - bytes).abs() / bytes, lessThan(0.01), reason: '$est vs $bytes');
      });
    });

    test('최고 화질은 2160p: H.264 가 없으면 용량이 큰 VP9(315)+258', () {
      final est = estimateVideoBytes(bbb, null)!;
      // 315(1299.2MiB) + 258(30,767,611B) 를 yt-dlp 가 실제로 선택함
      expect(est, closeTo(1299.2 * 1024 * 1024 + 30767611, 3 * 1024 * 1024));
    });
  });

  test('구간 자르기는 길이 비율만큼 줄어든다', () {
    final bbb = load('bbb');
    final full = estimateVideoBytes(bbb, 720)!;
    final part = estimateVideoBytes(bbb, 720, fraction: 0.1)!;
    expect(part, closeTo(full * 0.1, 1));
  });

  test('M4A 는 AAC 스트림 용량, MP3 는 비트레이트 기준 어림값', () {
    final bbb = load('bbb');
    expect(estimateAudioBytes(bbb, 'm4a'), 30767611); // 258
    // 635초 x 230kbps
    expect(estimateAudioBytes(bbb, 'mp3'), closeTo(635 * 230000 / 8, 1));
  });

  test('화질 제한보다 낮은 영상(2005년 240p)은 가장 가까운 화질로 계산', () {
    final zoo = load('zoo');
    expect(estimateVideoBytes(zoo, 1080), isNotNull);
    expect(estimateVideoBytes(zoo, 360), isNotNull);
  });

  test('포맷 정보가 없으면 null', () {
    final empty = MediaInfo(id: 'x', title: 't', uploader: '', url: 'u', durationSeconds: 10);
    expect(estimateVideoBytes(empty, 720), isNull);
  });

  test('용량 표기', () {
    expect(formatBytes(28526904), '27.2MB');
    expect(formatBytes(288387264), '275MB');
    expect(formatBytes(1363000000), '1.3GB');
    expect(formatBytes(500 * 1024), '500KB');
  });
}
