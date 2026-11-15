// 실제 Windows 앱으로 영상 편집 탭을 검증한다: 영상 열기 -> 재생 -> 구간 선택 -> 새 파일 저장(복사/다시 인코딩).
//
//   flutter test integration_test/video_editor_windows_test.dart -d windows
//
// 주의: 이 테스트는 build\windows\...\Debug\ytdl.exe 를 테스트용으로 덮어쓴다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/backend/desktop_backend.dart';
import 'package:ytdl/main.dart';
import 'package:ytdl/screens/video_edit_page.dart';

const _dir = r'C:\myapp\tmp\ytdl_vid_it';

Future<void> pumpUntil(WidgetTester t, bool Function() cond,
    {Duration timeout = const Duration(seconds: 60), String what = ''}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? '')
          .where((s) => s.isNotEmpty)
          .join(' | ');
      throw TestFailure('시간 초과: $what\n화면 글자: $texts');
    }
    await t.pump(const Duration(milliseconds: 200));
  }
}

double durationOf(String ffmpeg, String path) {
  final r = Process.runSync(ffmpeg, ['-hide_banner', '-nostdin', '-i', path]);
  final m = RegExp(r'Duration: (\d+):(\d+):(\d+\.\d+)').firstMatch('${r.stderr}')!;
  return int.parse(m.group(1)!) * 3600 + int.parse(m.group(2)!) * 60 + double.parse(m.group(3)!);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('영상 편집 탭', (t) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saveDir', _dir);
    if (Directory(_dir).existsSync()) Directory(_dir).deleteSync(recursive: true);
    Directory(_dir).createSync(recursive: true);

    // 알려진 접근성 트리 assertion 은 따로 세고 넘어간다(windows_flow_test 참고).
    var semanticsAsserts = 0;
    final prevOnError = FlutterError.onError;
    FlutterError.onError = (d) {
      final msg = d.exceptionAsString();
      if (msg.contains('seenChildren.add(child)') || msg.contains('node.built')) {
        semanticsAsserts++;
        return;
      }
      prevOnError?.call(d);
    };
    addTearDown(() => FlutterError.onError = prevOnError);

    final ffmpeg = '${Platform.environment['LOCALAPPDATA']}\\YTDL\\bin\\ffmpeg.exe';
    final src = '$_dir\\시험 영상.mp4'; // 한글 이름도 확인
    final gen = Process.runSync(ffmpeg, [
      '-nostdin', '-y', '-loglevel', 'error',
      '-f', 'lavfi', '-i', 'testsrc=size=640x360:rate=30',
      '-f', 'lavfi', '-i', 'sine=frequency=440',
      '-t', '30', '-c:v', 'libx264', '-g', '60', '-pix_fmt', 'yuv420p', '-c:a', 'aac', src,
    ]);
    expect(gen.exitCode, 0, reason: '${gen.stderr}');

    await t.pumpWidget(YtdlApp(backend: DesktopBackend()));
    await pumpUntil(t, () => find.byType(VideoEditPage, skipOffstage: false).evaluate().isNotEmpty,
        timeout: const Duration(minutes: 3), what: '앱 시작');
    await pumpUntil(t, () => find.byType(TextField).evaluate().isNotEmpty, what: '메인 화면');

    // 영상 편집 탭으로 가서 파일을 연다.
    final navVideo = find.byType(NavigationBar).evaluate().isNotEmpty
        ? find.descendant(of: find.byType(NavigationBar), matching: find.text('영상 편집'))
        : find.widgetWithText(TextButton, '영상 편집');
    await t.tap(navVideo);
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('편집할 영상을 열어 주세요'), findsOneWidget);
    final page = t.widget<VideoEditPage>(find.byType(VideoEditPage));
    page.controller.openLocal(src, recent: page.recent);

    // 영상이 열리고 길이(30초)를 읽는다.
    await pumpUntil(t, () => find.textContaining('30', skipOffstage: false).evaluate().isNotEmpty && find.byTooltip('선택 구간 재생').evaluate().isNotEmpty,
        what: '영상 열기(길이 읽기)');
    expect(find.text('시험 영상'), findsOneWidget); // 파일 이름(한글, 확장자 없이)이 제목 줄에 보임

    // 재생: 위치가 앞으로 가고 정지 버튼으로 멈춘다.
    await t.tap(find.byTooltip('선택 구간 재생'));
    await pumpUntil(t, () => find.byTooltip('정지').evaluate().isNotEmpty, what: '재생 시작');
    final started = DateTime.now();
    await pumpUntil(t, () => DateTime.now().difference(started) > const Duration(milliseconds: 2000));
    await t.tap(find.byTooltip('정지'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('선택 구간 재생'), findsOneWidget, reason: '정지 후 다시 재생 버튼');
    final posText = find.textContaining(RegExp(r'^0:0[1-9]\.\d$'));
    expect(posText, findsWidgets, reason: '재생 위치 표시가 앞으로 이동');

    // 구간 10~18초 선택 -> 길이 0:08
    Finder field(String label) => find.widgetWithText(TextField, label);
    await t.ensureVisible(field('시작'));
    await t.enterText(field('시작'), '0:10');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.enterText(field('끝'), '0:18');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.textContaining('잘라낼 길이 0:08'), findsOneWidget);

    // 선택 구간 재생은 구간 끝에서 저절로 멈춘다.
    await t.ensureVisible(find.byTooltip('끝 부분 듣기'));
    await t.pump();
    await t.tap(find.byTooltip('끝 부분 듣기')); // 끝 3초만
    await pumpUntil(t, () => find.byTooltip('정지').evaluate().isNotEmpty, what: '끝 부분 재생 시작');
    await pumpUntil(t, () => find.byTooltip('선택 구간 재생').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15), what: '끝에서 자동 정지');

    // 저장 1) 빠르게(복사)
    final saveBtn = find.textContaining('선택 구간 새 파일로 저장');
    await t.ensureVisible(saveBtn);
    await t.tap(saveBtn);
    await pumpUntil(t, () => find.textContaining('새 파일로 저장했어요').evaluate().isNotEmpty, what: '빠른 저장');
    var files = Directory(_dir).listSync().whereType<File>().map((f) => f.path).toList();
    final copy = files.where((p) => p.contains('(cut 0m10s-0m18s)')).toList();
    expect(copy, hasLength(1), reason: '$files');
    expect(durationOf(ffmpeg, copy.single), closeTo(8, 2.5));

    // 새 파일이 편집 대상이 되었다(길이 약 8초) -> 정확하게(다시 인코딩)로 2~5초를 한 번 더
    await pumpUntil(
        t,
        () => find.textContaining('(전체 0:30)').evaluate().isEmpty && find.textContaining('(전체 0:0').evaluate().isNotEmpty,
        what: '새 파일로 교체(길이 약 8초)');
    await t.pump(const Duration(seconds: 1));
    await t.ensureVisible(find.text('정확하게'));
    await t.pump(const Duration(milliseconds: 600));
    await t.tap(find.text('정확하게'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('MP4로 저장돼요'), findsOneWidget, reason: '정확하게 모드 설명으로 바뀜');
    await t.ensureVisible(field('시작'));
    await t.enterText(field('시작'), '0:02');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.enterText(field('끝'), '0:05');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    final save2 = find.textContaining('선택 구간 새 파일로 저장');
    await t.ensureVisible(save2);
    await t.tap(save2);
    await pumpUntil(t, () => Directory(_dir).listSync().any((e) => e.path.contains('cut 0m12s-0m15s')),
        timeout: const Duration(seconds: 120), what: '정확한 저장(다시 인코딩)');
    files = Directory(_dir).listSync().whereType<File>().map((f) => f.path).toList();
    final exact = files.where((p) => p.contains('cut 0m12s-0m15s')).toList();
    expect(exact, hasLength(1), reason: '원본 기준 시각으로 이름이 이어짐: $files');
    expect(exact.single, endsWith('.mp4'));
    expect(durationOf(ffmpeg, exact.single), closeTo(3, 0.3));
    expect(File(src).existsSync(), isTrue, reason: '원본은 그대로');

    await prefs.remove('saveDir');
    // ignore: avoid_print
    print('접근성 트리 assertion 횟수: $semanticsAsserts');
  });
}
