// 편집기 화면에서 ▶ 를 눌렀을 때 소리가 얼마나 늦게 시작하는지 잰다.
// 화면의 재생 위치 글자("0:01.2 / 0:07.0")를 짧은 간격으로 읽어 (실제 경과 - 재생 위치) 를 계산한다.
//
//   flutter test integration_test/editor_latency_test.dart -d windows                       (준비운동 끔)
//   flutter test integration_test/editor_latency_test.dart -d windows --dart-define=PRIME=true  (준비운동 켬)
// Android 는 -d <기기> 로 같은 방식. 샘플 mp3 는 앱 전용 폴더에 adb push 해 둔다(위 _file 참고).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ytdl/backend/desktop_backend.dart';
import 'package:ytdl/main.dart';
import 'package:ytdl/screens/edit_page.dart';

final _file = Platform.isAndroid
    ? '/sdcard/Android/data/com.ytdl.ytdl/files/latency_sample.mp3'
    : r'C:\myapp\tmp\latency_sample.mp3';

final _pos = RegExp(r'^(\d+):(\d\d)\.(\d) / ');

int? currentPosMs(WidgetTester t) {
  for (final e in find.byType(Text).evaluate()) {
    final s = (e.widget as Text).data;
    final m = s == null ? null : _pos.firstMatch(s);
    if (m != null) {
      return (int.parse(m[1]!) * 60 + int.parse(m[2]!)) * 1000 + int.parse(m[3]!) * 100;
    }
  }
  return null;
}

Future<void> waitMs(WidgetTester t, int ms) async {
  final sw = Stopwatch()..start();
  while (sw.elapsedMilliseconds < ms) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

/// ▶ 를 누른 뒤 [ms] 동안 (경과, 위치) 표본을 모은다. 반환: (처음 위치가 움직이기까지 ms, 1초 시점 지연 ms)
Future<(int, int)> pressPlayAndMeasure(WidgetTester t, {int ms = 1600}) async {
  final p0 = currentPosMs(t) ?? 0;
  final sw = Stopwatch()..start();
  await t.tap(find.byTooltip('재생'));
  int? firstMove;
  var lagAt1s = -1;
  while (sw.elapsedMilliseconds < ms) {
    await t.pump(const Duration(milliseconds: 15));
    final moved = (currentPosMs(t) ?? p0) - p0;
    if (firstMove == null && moved > 0) firstMove = sw.elapsedMilliseconds;
    if (lagAt1s < 0 && sw.elapsedMilliseconds >= 1000) lagAt1s = sw.elapsedMilliseconds - moved;
  }
  await t.tap(find.byTooltip('일시정지'));
  await t.pump(const Duration(milliseconds: 200));
  return (firstMove ?? 9999, lagAt1s);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('편집기 첫 재생 지연', (t) async {
    expect(File(_file).existsSync(), isTrue, reason: '샘플 파일 필요: $_file');
    await t.pumpWidget(YtdlApp(backend: DesktopBackend()));
    final end = DateTime.now().add(const Duration(minutes: 3));
    while (find.byType(NavigationBar).evaluate().isEmpty && DateTime.now().isBefore(end)) {
      await t.pump(const Duration(milliseconds: 200));
    }

    await t.tap(find.text('음원 편집').first);
    await t.pump(const Duration(milliseconds: 300));
    final page = t.widget<EditPage>(find.byType(EditPage));

    final results = <String>[];
    final firsts = <int>[], seconds = <int>[], laters = <int>[];
    for (var round = 0; round < 5; round++) {
      // 같은 파일을 새로 연다(편집기가 새로 만들어져 플레이어도 새로 로드된다).
      page.controller.close();
      await t.pump(const Duration(milliseconds: 300));
      page.controller.openLocal(_file, recent: page.recent);
      // 편집기가 준비(파일 길이 읽기)될 때까지
      while (find.byTooltip('재생').evaluate().isEmpty) {
        await t.pump(const Duration(milliseconds: 20));
      }
      // 준비되자마자 바로 누르는 경우 (사용자가 가장 빨리 누를 때)
      final immediate = await pressPlayAndMeasure(t);

      // 같은 편집기에서 두 번째 재생
      final again = await pressPlayAndMeasure(t);

      // 새로 열고 3초 뒤에 누르는 경우
      page.controller.close();
      await t.pump(const Duration(milliseconds: 300));
      page.controller.openLocal(_file, recent: page.recent);
      while (find.byTooltip('재생').evaluate().isEmpty) {
        await t.pump(const Duration(milliseconds: 20));
      }
      await waitMs(t, 3000);
      final later = await pressPlayAndMeasure(t);

      firsts.add(immediate.$1);
      seconds.add(again.$1);
      laters.add(later.$1);
      results.add('라운드${round + 1}: 열자마자 첫 재생 (움직임 시작 ${immediate.$1}ms, 1초 지연 ${immediate.$2}ms)'
          ' | 두 번째 재생 (${again.$1}ms, ${again.$2}ms)'
          ' | 3초 뒤 첫 재생 (${later.$1}ms, ${later.$2}ms)');
    }
    // 평균: 첫 재생(열자마자 / 3초 뒤)과 두 번째 재생의 "움직임 시작" ms
    int avg(Iterable<int> v) => (v.reduce((a, b) => a + b) / v.length).round();
    // ignore: avoid_print
    print('\n[EDITOR-LATENCY] 준비운동 ${const bool.fromEnvironment('PRIME') ? "켬" : "끔"}\n'
        '${results.map((e) => '[EDITOR-LATENCY] $e').join('\n')}\n'
        '[EDITOR-LATENCY] 평균 움직임 시작(ms): 열자마자 첫 재생 ${avg(firsts)}, 두 번째 ${avg(seconds)}, 3초 뒤 첫 재생 ${avg(laters)}\n');
  });
}
