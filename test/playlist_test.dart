import 'package:flutter_test/flutter_test.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/util/youtube_url.dart';

void main() {
  group('재생목록 주소', () {
    test('재생목록 자체를 가리키는 주소만 재생목록으로 본다', () {
      expect(
        isPlaylistOnlyUrl('https://www.youtube.com/playlist?list=PLabc123'),
        isTrue,
      );
      expect(
        isPlaylistOnlyUrl('https://music.youtube.com/playlist?list=PLabc123'),
        isTrue,
      );
      // 영상이 지정돼 있으면 영상 하나로 본다.
      expect(
        isPlaylistOnlyUrl('https://www.youtube.com/watch?v=jNQXAC9IVRw&list=PLabc123'),
        isFalse,
      );
      expect(isPlaylistOnlyUrl('https://youtu.be/jNQXAC9IVRw?list=PLabc123'), isFalse);
      expect(isPlaylistOnlyUrl('https://www.youtube.com/watch?v=jNQXAC9IVRw'), isFalse);
      expect(isPlaylistOnlyUrl('not a url'), isFalse);
    });

    test('믹스(RD)와 개인 목록(WL, LL)은 재생목록으로 안 본다', () {
      expect(playlistIdOf('https://www.youtube.com/watch?v=jNQXAC9IVRw&list=RDjNQXAC9IVRw'), isNull);
      expect(playlistIdOf('https://www.youtube.com/playlist?list=WL'), isNull);
      expect(playlistIdOf('https://www.youtube.com/playlist?list=LL'), isNull);
      expect(playlistIdOf('https://www.youtube.com/watch?v=jNQXAC9IVRw&list=PLabc'), 'PLabc');
    });

    test('재생목록 ID 로 표준 주소를 만든다', () {
      expect(playlistUrlFor('PLabc'), 'https://www.youtube.com/playlist?list=PLabc');
    });
  });

  group('PlaylistInfo.fromJson', () {
    final json = {
      'title': '내 목록',
      'uploader': '채널',
      'playlist_count': 5,
      'entries': [
        {
          'id': 'AAAAAAAAAAA',
          'url': 'https://www.youtube.com/watch?v=AAAAAAAAAAA',
          'title': '첫 곡',
          'duration': 200,
          'channel': '가수',
          'thumbnails': [
            {'url': 'https://i.ytimg.com/small.jpg'},
            {'url': 'https://i.ytimg.com/big.jpg'},
          ],
        },
        {'id': 'BBBBBBBBBBB', 'title': '[Private video]'},
        {'id': 'CCCCCCCCCCC', 'title': '[Deleted video]'},
        {'id': 'DDDDDDDDDDD', 'title': '길이 모름'},
        {'title': 'id 없음'},
        'not a map',
      ],
    };

    test('받을 수 있는 영상만 남기고 건너뛴 수를 센다', () {
      final p = PlaylistInfo.fromJson(json, 'https://www.youtube.com/playlist?list=PLx');
      expect(p.title, '내 목록');
      expect(p.entries.map((e) => e.id), ['AAAAAAAAAAA', 'DDDDDDDDDDD']);
      expect(p.skipped, 3);
    });

    test('길이·썸네일·주소를 채운다', () {
      final p = PlaylistInfo.fromJson(json, 'u');
      final first = p.entries.first;
      expect(first.durationSeconds, 200);
      expect(first.uploader, '가수');
      expect(first.thumbnail, 'https://i.ytimg.com/big.jpg');
      final second = p.entries.last;
      expect(second.durationSeconds, isNull);
      expect(second.url, 'https://www.youtube.com/watch?v=DDDDDDDDDDD');
      expect(second.thumbnail, 'https://i.ytimg.com/vi/DDDDDDDDDDD/mqdefault.jpg');
    });

    test('앞부분만 읽었으면 truncated', () {
      // 목록은 9개인데 읽은 2개 + 건너뛴 3개 뿐이다.
      final p = PlaylistInfo.fromJson({...json, 'playlist_count': 9}, 'u');
      expect(p.truncated, isTrue);
      expect(p.totalCount, 9);
    });

    test('전부 읽었으면 truncated 가 아니다', () {
      // 읽은 2개 + 건너뛴 3개 = 5개 → 전부 읽음
      expect(PlaylistInfo.fromJson(json, 'u').truncated, isFalse);
    });
  });
}
