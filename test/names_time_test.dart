import 'package:flutter_test/flutter_test.dart';
import 'package:ytdl/util/names.dart';
import 'package:ytdl/util/time_format.dart';

void main() {
  group('clockTag / 파일 이름', () {
    test('정수 초', () {
      expect(clockTag(5), '0m05s');
      expect(clockTag(65), '1m05s');
      expect(clockTag(3723), '1h02m03s');
    });
    test('소수 초는 0.1초 단위까지', () {
      expect(clockTag(6.3), '0m06.3s');
      expect(clockTag(6.04), '0m06s'); // 0.1초 미만은 반올림
      expect(clockTag(59.96), '1m00s');
    });
    test('잘린 이름 접미사와 되돌리기', () {
      expect(cutSuffix(5, 12), ' (cut 0m05s-0m12s)');
      expect(stripCut('Me at the zoo (cut 0m05s-0m12s)'), 'Me at the zoo');
      expect(stripCut('Song (live) (cut 1m00s-2m00s)'), 'Song (live)');
      expect(stripCut('No cut here'), 'No cut here');
    });
    test('경로에서 이름/확장자', () {
      expect(baseNameOf(r'C:\Users\a\Downloads\YTDL\내 노래 (cut 0m05s-0m12s).mp3'), '내 노래 (cut 0m05s-0m12s)');
      expect(baseNameOf('/storage/emulated/0/Music/YTDL/a.b.m4a'), 'a.b');
      expect(extensionOf('/x/y/z.opus'), 'opus');
    });
  });

  group('파일 이름에서 원본 기준 구간 읽기', () {
    test('clockTag 와 서로 되돌릴 수 있다', () {
      for (final s in [5.0, 65.0, 6.3, 3723.0, 3723.5, 0.0]) {
        expect(parseClockTag(clockTag(s)), closeTo(s, 0.05));
      }
      expect(parseClockTag('abc'), isNull);
    });
    test('parseCutTag', () {
      final t = parseCutTag('Me at the zoo (cut 0m05s-0m12s)')!;
      expect(t.start, 5);
      expect(t.end, 12);
      final u = parseCutTag('내 노래 (cut 1m05.5s-1h02m03s)')!;
      expect(u.start, 65.5);
      expect(u.end, 3723);
      expect(parseCutTag('Song (live)'), isNull);
      expect(parseCutTag('Song (cut 0m10s-0m05s)'), isNull, reason: '끝이 시작보다 앞이면 무시');
    });
  });

  group('formatMs / parseMs', () {
    test('표시', () {
      expect(formatMs(0), '0:00.0');
      expect(formatMs(3250), '0:03.3'); // 0.1초로 반올림
      expect(formatMs(83400), '1:23.4');
      expect(formatMs(3723000), '1:02:03.0');
    });
    test('입력 해석', () {
      expect(parseMs('83.5'), 83500);
      expect(parseMs('1:23.4'), 83400);
      expect(parseMs('1:02:03'), 3723000);
      expect(parseMs(' 0:05 '), 5000);
    });
    test('잘못된 입력', () {
      expect(parseMs(''), isNull);
      expect(parseMs('abc'), isNull);
      expect(parseMs('1:2:3:4'), isNull);
      expect(parseMs('-1'), isNull);
    });
    test('표시했다가 다시 읽어도 같다', () {
      for (final ms in [0, 100, 5000, 12300, 83400]) {
        expect(parseMs(formatMs(ms)), ms);
      }
    });
  });
}
