// 실제 Windows 앱을 띄워 첫 실행(도구 준비) -> 링크 조회 -> 음원 구간 자르기 -> 미리듣기·다듬기 ->
// 영상 다운로드까지 전 과정을 진짜 DesktopBackend 로 검증한다. (네트워크 필요)
//
//   flutter test integration_test/windows_flow_test.dart -d windows
//
// 주의: 이 테스트는 build\windows\...\Debug\ytdl.exe 를 테스트용으로 덮어쓴다.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/backend/desktop_backend.dart';
import 'package:ytdl/main.dart';
import 'package:ytdl/screens/edit_page.dart';
import 'package:ytdl/widgets/audio_editor.dart';

const _outDir = r'C:\myapp\tmp\ytdl_it_out';
const _url = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';

/// 화면 밖(스크롤 아래)에 있는 위젯도 보이게 스크롤한 뒤 누른다.
Future<void> tapIt(WidgetTester t, Finder f) async {
  await t.ensureVisible(f);
  await t.pump();
  await t.tap(f);
}

/// 실제 비동기 I/O 가 끝날 때까지 프레임을 돌리며 기다린다.
Future<void> pumpUntil(
  WidgetTester t,
  bool Function() cond, {
  Duration timeout = const Duration(minutes: 5),
  String what = '',
}) async {
  final end = DateTime.now().add(timeout);
  while (!cond()) {
    if (DateTime.now().isAfter(end)) {
      // 무엇이 화면에 떠 있었는지 같이 남겨 원인을 바로 볼 수 있게 한다.
      final texts = find
          .byType(Text)
          .evaluate()
          .map((e) => (e.widget as Text).data ?? (e.widget as Text).textSpan?.toPlainText() ?? '')
          .where((s) => s.isNotEmpty)
          .join(' | ');
      // 목록은 보이는 부분만 그려지므로, 진행 상태를 알려 주는 글자는 따로 찾아 둔다.
      final probes = ['시작하는 중', '다운로드 중', '변환 중', '저장 중', '취소', '저장 완료', '취소했습니다']
          .where((k) => find.textContaining(k, skipOffstage: false).evaluate().isNotEmpty)
          .toList();
      // 화면에 안 보여도 실제로 일이 끝났는지 알 수 있게 파일과 프로세스를 직접 확인한다.
      String alive(String exe) {
        final r = Process.runSync('tasklist', ['/FI', 'IMAGENAME eq $exe', '/NH']);
        return (r.stdout as String).contains(exe) ? '실행 중' : '없음';
      }

      final outFiles = Directory(_outDir).existsSync()
          ? Directory(_outDir)
              .listSync()
              .whereType<File>()
              .map((f) => '${f.uri.pathSegments.last}(${f.lengthSync()}B)')
              .toList()
          : [];
      throw TestFailure('시간 초과: $what\n'
          'yt-dlp.exe: ${alive('yt-dlp.exe')}, ffmpeg.exe: ${alive('ffmpeg.exe')}, deno.exe: ${alive('deno.exe')}\n'
          '출력 폴더 파일: $outFiles\n'
          '진행 상태 글자: $probes\n'
          '프레임 예약됨: ${t.binding.hasScheduledFrame}\n'
          '화면 글자: $texts');
    }
    await t.pump(const Duration(milliseconds: 200));
  }
}

/// ffprobe 로 실제 파일 길이(초)를 잰다.
Future<double> probeDuration(String path) async {
  final bin = '${Platform.environment['LOCALAPPDATA']}\\YTDL\\bin\\ffprobe.exe';
  final r = await Process.run(
      bin, ['-v', 'error', '-show_entries', 'format=duration', '-of', 'csv=p=0', path]);
  return double.parse((r.stdout as String).trim());
}

List<String> filesIn(String dir) =>
    Directory(dir).listSync().whereType<File>().map((f) => f.path).toList();

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Windows 전체 흐름', (t) async {
    // 저장 폴더를 테스트 전용으로 지정(사용자 Downloads 를 어지럽히지 않음).
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saveDir', _outDir);
    if (Directory(_outDir).existsSync()) Directory(_outDir).deleteSync(recursive: true);

    await t.pumpWidget(YtdlApp(backend: DesktopBackend()));

    // 1) 첫 실행: 도구 준비 -> 메인 화면
    await pumpUntil(t, () => find.byType(TextField).evaluate().isNotEmpty,
        what: '엔진 준비(내려받기) 후 메인 화면');
    final bin = '${Platform.environment['LOCALAPPDATA']}\\YTDL\\bin';
    for (final f in ['yt-dlp.exe', 'ffmpeg.exe', 'deno.exe']) {
      expect(File('$bin\\$f').existsSync(), isTrue, reason: '$f 준비됨');
    }

    // 2) 링크 조회 + 예상 용량 표시
    await t.enterText(find.byType(TextField).first, _url);
    await tapIt(t, find.text('조회'));
    await pumpUntil(t, () => find.text('Me at the zoo').evaluate().isNotEmpty,
        what: '영상 정보 표시');
    expect(find.textContaining('약 '), findsWidgets, reason: '예상 용량 표시');

    // 3) 음원(MP3) 구간 자르기 5~12초
    await tapIt(t, find.text('필요한 구간만 잘라서 저장'));
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, '시작'), '0:05');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.enterText(find.widgetWithText(TextField, '끝'), '0:12');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.textContaining('잘라낼 길이 0:07'), findsOneWidget);

    await tapIt(t, find.widgetWithText(FilledButton, '다운로드'));
    await pumpUntil(t, () => find.text('저장 완료').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 90), what: '음원 다운로드 완료');
    var files = filesIn(_outDir);
    expect(files.where((p) => p.endsWith('.mp3') && p.contains('cut 0m05s-0m12s')), hasLength(1));

    // 4) "편집하기" -> 편집 탭으로 이동해 방금 받은 음원이 열린다
    expect(find.text('미리듣기 · 다듬기'), findsNothing, reason: '편집기는 편집 탭에만 있다');
    await tapIt(t, find.text('편집하기 (듣고 구간 자르기)'));
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('미리듣기 · 다듬기'), findsOneWidget);
    expect(find.text('최근 파일'), findsOneWidget, reason: '받은 파일이 최근 목록에 오름');
    await pumpUntil(t, () => find.textContaining('선택 구간만 새 파일로 저장').evaluate().isNotEmpty || find.textContaining('자를 구간을 먼저').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30), what: '편집기 준비(파일 길이 읽기)');
    expect(find.textContaining('이 파일 = 원본 영상 0:05.0 ~ 0:12.0 구간'), findsOneWidget);
    expect(find.textContaining('0:07.0'), findsWidgets, reason: '파일 길이 7.0초');

    // 4-1) 재생: 위치가 실제로 앞으로 간다
    await tapIt(t, find.byTooltip('재생'));
    await pumpUntil(t, () => find.byTooltip('일시정지').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15), what: '재생 시작');
    final started = DateTime.now();
    await pumpUntil(t, () => DateTime.now().difference(started) > const Duration(milliseconds: 1800));
    await tapIt(t, find.byTooltip('일시정지'));
    await t.pump(const Duration(milliseconds: 500));
    final posLabel = find.textContaining(RegExp(r'^\d:\d\d\.\d / 0:07\.0')).evaluate().first.widget as Text;
    expect(posLabel.data, isNot(startsWith('0:00.0 /')), reason: '재생 위치가 앞으로 이동: ${posLabel.data}');

    // 4-2) 파일 안에서 2.0~5.0초 구간 선택 -> 원본 기준 7.0~10.0초
    final editor = find.byType(AudioEditor);
    Finder field(String label) =>
        find.descendant(of: editor, matching: find.widgetWithText(TextField, label));
    await t.enterText(field('시작'), '2');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.enterText(field('끝'), '5');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.textContaining('이 파일 0:02.0 ~ 0:05.0  (3.0초)'), findsOneWidget);
    expect(find.textContaining('→ 원본 영상 0:07.0 ~ 0:10.0'), findsOneWidget);

    // 4-3) 선택 구간 듣기가 자동으로 멈추는지(끝에서 정지)
    await tapIt(t, find.text('선택 구간 듣기'));
    await pumpUntil(t, () => find.byTooltip('일시정지').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15), what: '구간 듣기 시작');
    await pumpUntil(t, () => find.byTooltip('재생').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 15), what: '구간 끝에서 자동 정지');

    // 4-4) 새 파일로 저장 -> 원본(5~12초)은 그대로, 7~10초 파일이 추가됨
    await tapIt(t, find.text('선택 구간만 새 파일로 저장'));
    await pumpUntil(t, () => find.textContaining('새 파일로 저장했어요').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60), what: '새 파일 저장');
    files = filesIn(_outDir);
    final cut1 = files.where((p) => p.contains('cut 0m07s-0m10s')).toList();
    expect(cut1, hasLength(1), reason: '새 파일 생성: $files');
    expect(await probeDuration(cut1.single), closeTo(3.0, 0.1));
    expect(files.where((p) => p.contains('cut 0m05s-0m12s')), hasLength(1), reason: '원본 파일은 그대로');

    // 4-5) 새 파일이 편집 대상이 되고, 한 번 더 자를 수 있다(0.5~2.5초 -> 원본 7.5~9.5초)
    await pumpUntil(t, () => find.textContaining('이 파일 = 원본 영상 0:07.0 ~ 0:10.0 구간').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30), what: '새 파일로 편집기 교체');
    await pumpUntil(t, () => find.textContaining('자를 구간을 먼저 골라 주세요').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30), what: '새 파일 길이 읽기');
    await t.enterText(field('시작'), '0.5');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.enterText(field('끝'), '2.5');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.textContaining('→ 원본 영상 0:07.5 ~ 0:09.5'), findsOneWidget);
    await tapIt(t, find.text('선택 구간만 새 파일로 저장'));
    await pumpUntil(t, () => find.textContaining('cut 0m07.5s-0m09.5s').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60), what: '두 번째 새 파일 저장');
    files = filesIn(_outDir);
    final cut2 = files.where((p) => p.contains('cut 0m07.5s-0m09.5s')).toList();
    expect(cut2, hasLength(1), reason: '$files');
    expect(await probeDuration(cut2.single), closeTo(2.0, 0.1));

    // 4-6) 컴퓨터에 있는 일반 음원(원본 정보 없음, 한글 이름)을 열어 자르기
    final localDir = r'C:\myapp\tmp\ytdl_it_local';
    if (Directory(localDir).existsSync()) Directory(localDir).deleteSync(recursive: true);
    Directory(localDir).createSync(recursive: true);
    final localPath = '$localDir\\내 노래.mp3';
    File(cut1.single).copySync(localPath);

    final editPage = t.widget<EditPage>(find.byType(EditPage));
    editPage.controller.openLocal(localPath, recent: editPage.recent);
    await pumpUntil(t, () => find.textContaining('내 노래').evaluate().isNotEmpty && find.textContaining('자를 구간을 먼저').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30), what: '일반 파일 열기');
    expect(find.textContaining('이 파일 = '), findsNothing, reason: '원본 정보가 없는 일반 파일은 원본 구간을 안 보여 줌');
    await t.enterText(field('시작'), '1');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    await t.enterText(field('끝'), '2');
    await t.testTextInput.receiveAction(TextInputAction.done);
    await t.pump();
    expect(find.textContaining('선택: 이 파일 0:01.0 ~ 0:02.0  (1.0초)'), findsOneWidget);
    expect(find.textContaining('→ '), findsNothing);
    await tapIt(t, find.text('선택 구간만 새 파일로 저장'));
    await pumpUntil(t, () => find.textContaining('새 파일로 저장했어요').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 60), what: '일반 파일 자르기 저장');
    final localOut = '$localDir\\내 노래 (cut 0m01s-0m02s).mp3';
    expect(File(localOut).existsSync(), isTrue, reason: '원본과 같은 폴더에 저장: ${filesIn(localDir)}');
    expect(await probeDuration(localOut), closeTo(1.0, 0.1));
    expect(File(localPath).existsSync(), isTrue, reason: '원본은 그대로');
    // 저장 후 이 파일이 새 편집 대상이 되고, 이제부터 "원본 파일" 기준을 보여 준다
    await pumpUntil(t, () => find.textContaining('이 파일 = 원본 파일 0:01.0 ~ 0:02.0 구간').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30), what: '원본 파일 기준 표시');

    // 4-7) 이 앱이 이전에 자른 파일을 다시 열면 원본 기준 구간을 이어받는다
    editPage.controller.openLocal(cut1.single, recent: editPage.recent);
    await pumpUntil(t, () => find.textContaining('이 파일 = 원본 0:07.0 ~ 0:10.0 구간').evaluate().isNotEmpty,
        timeout: const Duration(seconds: 30), what: '잘린 파일 다시 열기');

    // 5) 영상 탭 360p, 구간 없이 전체  (다운로드 탭으로 돌아가 위로 스크롤)
    await tapIt(t, find.descendant(of: find.byType(NavigationBar), matching: find.text('다운로드')));
    await t.pump(const Duration(milliseconds: 500));
    await t.drag(find.byType(ListView), const Offset(0, 3000));
    await t.pump(const Duration(milliseconds: 500));
    await tapIt(t, find.text('영상'));
    await t.pump();
    await tapIt(t, find.text('360p'));
    await t.pump();
    await tapIt(t, find.text('필요한 구간만 잘라서 저장')); // 끄기
    await t.pump();
    await tapIt(t, find.widgetWithText(FilledButton, '다운로드'));
    await t.pump(); // _downloading = true 반영(이전 결과 카드와 편집 버튼 사라짐)
    expect(find.text('취소'), findsOneWidget, reason: '다운로드 중 표시');
    expect(find.text('편집하기 (듣고 구간 자르기)'), findsNothing);
    await pumpUntil(t, () => find.text('저장 완료').evaluate().isNotEmpty,
        what: '영상 다운로드 완료');
    files = filesIn(_outDir);
    expect(files.where((p) => p.endsWith('.mp4')), isNotEmpty);
    expect(find.text('편집하기 (듣고 구간 자르기)'), findsNothing, reason: '영상은 음원 편집 대상이 아님');

    await prefs.remove('saveDir');
  });
}
