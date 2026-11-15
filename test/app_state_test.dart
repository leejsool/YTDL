import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/state/app_state.dart';

void main() {
  group('EditController.fromLocalFile', () {
    test('일반 파일: 원본 정보 없음, 이름 그대로', () {
      final a = EditController.fromLocalFile(r'C:\Music\내 노래.mp3');
      expect(a.title, '내 노래');
      expect(a.sourceLabel, isNull);
      expect(a.srcStart, 0);
      expect(a.path, r'C:\Music\내 노래.mp3');
    });

    test('이 앱이 자른 파일을 다시 열면 원본 기준 구간을 이어 받는다', () {
      final a = EditController.fromLocalFile(r'C:\x\Me at the zoo (cut 0m07s-0m10s).mp3');
      expect(a.title, 'Me at the zoo');
      expect(a.sourceLabel, '원본');
      expect(a.srcStart, 7);
      expect(a.srcEnd, 10);
    });

    test('Android 선택 파일: 캐시 경로 대신 표시 이름을 쓴다', () {
      final a = EditController.fromLocalFile('/data/user/0/app/cache/file_picker/abc.m4a',
          displayName: '좋아하는 곡.m4a');
      expect(a.title, '좋아하는 곡');
      expect(a.location, '좋아하는 곡.m4a');
    });
  });

  group('EditController 동작', () {
    test('open 은 탭 이동 요청 횟수를 올리고 replace 는 올리지 않는다', () {
      final c = EditController();
      var notified = 0;
      c.addListener(() => notified++);
      const a = SavedAudio(title: 'a', path: 'p', location: 'l', srcStart: 0, srcEnd: 0);
      c.open(a);
      expect(c.openRequests, 1);
      c.replace(a);
      expect(c.openRequests, 1);
      expect(notified, 2);
    });
  });

  group('RecentStore', () {
    late Directory tmp;

    setUp(() {
      tmp = Directory.systemTemp.createTempSync('recent_test');
      SharedPreferences.setMockInitialValues({});
    });
    tearDown(() => tmp.deleteSync(recursive: true));

    SavedAudio audio(String name) {
      final f = File('${tmp.path}${Platform.pathSeparator}$name')..writeAsStringSync('x');
      return SavedAudio(
          title: name, path: f.path, location: f.path, srcStart: 1.5, srcEnd: 9, sourceLabel: '원본 영상');
    }

    test('최신이 맨 앞, 같은 파일은 중복 없이 앞으로', () async {
      final s = RecentStore();
      final a = audio('a.mp3'), b = audio('b.mp3');
      await s.add(a);
      await s.add(b);
      await s.add(a);
      expect(s.items.map((x) => x.title), ['a.mp3', 'b.mp3']);
    });

    test('저장했다가 다시 불러오면 같고, 지워진 파일은 빠진다', () async {
      final s = RecentStore();
      final a = audio('a.mp3'), b = audio('b.mp3');
      await s.add(a);
      await s.add(b);

      final s2 = RecentStore();
      await s2.load();
      expect(s2.items.length, 2);
      expect(s2.items.first.srcStart, 1.5);
      expect(s2.items.first.sourceLabel, '원본 영상');

      File(a.path).deleteSync();
      final s3 = RecentStore();
      await s3.load();
      expect(s3.items.map((x) => x.title), ['b.mp3']);
    });

    test('최대 ${RecentStore.maxItems}개', () async {
      final s = RecentStore();
      for (var i = 0; i < RecentStore.maxItems + 5; i++) {
        await s.add(audio('f$i.mp3'));
      }
      expect(s.items.length, RecentStore.maxItems);
      expect(s.items.first.title, 'f${RecentStore.maxItems + 4}.mp3');
    });
  });
}
