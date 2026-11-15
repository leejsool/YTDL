import 'package:flutter_test/flutter_test.dart';
import 'package:ytdl/util/youtube_url.dart';

void main() {
  group('findYoutubeUrl', () {
    test('일반 주소 / 짧은 주소 / 모바일 / 뮤직', () {
      expect(
        findYoutubeUrl('https://www.youtube.com/watch?v=abc123'),
        'https://www.youtube.com/watch?v=abc123',
      );
      expect(findYoutubeUrl('https://youtu.be/abc123?si=x'), 'https://youtu.be/abc123?si=x');
      expect(
        findYoutubeUrl('https://m.youtube.com/watch?v=abc123'),
        'https://m.youtube.com/watch?v=abc123',
      );
      expect(
        findYoutubeUrl('https://music.youtube.com/watch?v=abc123'),
        'https://music.youtube.com/watch?v=abc123',
      );
    });

    test('글 속에 섞여 있어도 주소만 뽑는다', () {
      expect(
        findYoutubeUrl('이 영상 좋아요 https://youtu.be/abc123 보세요'),
        'https://youtu.be/abc123',
      );
    });

    test('유튜브가 아니면 null', () {
      expect(findYoutubeUrl('https://example.com/watch?v=abc'), isNull);
      expect(findYoutubeUrl('https://notyoutube.com/watch'), isNull);
      expect(findYoutubeUrl('https://youtube.com.evil.com/x'), isNull);
      expect(findYoutubeUrl('그냥 글'), isNull);
      expect(findYoutubeUrl(''), isNull);
      expect(findYoutubeUrl(null), isNull);
    });
  });
}
