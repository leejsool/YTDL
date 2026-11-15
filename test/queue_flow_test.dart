import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/backend/backend.dart';
import 'package:ytdl/main.dart';
import 'package:ytdl/models.dart';

class _Backend extends Backend {
  final downloaded = <String>[];
  final optionsSeen = <DownloadOptions>[];

  @override
  String get saveLocationLabel => 'Downloads/YTDL';
  @override
  Future<void> prepare(SetupCallback onStatus) async {}

  @override
  Future<MediaInfo> fetchInfo(String url) async => MediaInfo(
    id: 'test',
    title: '영상 제목',
    uploader: '채널',
    url: url,
    durationSeconds: 82,
  );

  @override
  Future<PlaylistInfo> fetchPlaylist(String url, {int limit = 200}) async =>
      PlaylistInfo(
        title: '내 재생목록',
        uploader: '채널',
        url: url,
        entries: const [
          PlaylistEntry(id: 'a', title: '첫째 곡', url: 'https://x/a', durationSeconds: 100),
          PlaylistEntry(id: 'b', title: '둘째 곡', url: 'https://x/b', durationSeconds: 120),
          PlaylistEntry(id: 'c', title: '셋째 곡', url: 'https://x/c'),
        ],
      );

  @override
  Future<double> measureGain(
    String source,
    CancelToken token, {
    bool remote = false,
    double? startSec,
    double? endSec,
  }) async => 0;

  @override
  Future<DownloadResult> download(
    String url,
    DownloadOptions options,
    void Function(DownloadProgress) onProgress,
    CancelToken token,
  ) async {
    downloaded.add(url);
    optionsSeen.add(options);
    onProgress(const DownloadProgress(percent: .5, stage: '다운로드 중'));
    return DownloadResult(location: 'C:/out', filePath: 'C:/out/${url.split('/').last}.mp3');
  }

  @override
  Future<DownloadResult> trimAudio(
    String srcPath,
    double startSec,
    double endSec,
    String outBaseName, {
    AudioGain gain = const AudioGain.none(),
  }) async => throw UnimplementedError();

  @override
  Future<String> updateEngine() async => '';
}

void main() {
  for (final wide in [true, false]) {
    final name = wide ? 'wide' : 'mobile';

    Future<void> openQueueTab(WidgetTester tester) async {
      final tab = wide
          ? find.widgetWithText(TextButton, '대기열')
          : find.descendant(
              of: find.byType(NavigationBar),
              matching: find.text('대기열'),
            );
      await tester.tap(tab);
      await tester.pumpAndSettle();
    }

    Future<_Backend> start(WidgetTester tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = wide ? const Size(1200, 850) : const Size(360, 780);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final backend = _Backend();
      await tester.pumpWidget(YtdlApp(backend: backend));
      await tester.pumpAndSettle();
      return backend;
    }

    testWidgets('$name: 재생목록에서 고른 영상이 대기열로 가서 받아진다', (tester) async {
      final backend = await start(tester);

      await tester.enterText(
        find.byType(TextField),
        'https://www.youtube.com/playlist?list=PLtest',
      );
      await tester.tap(find.byTooltip('조회'));
      await tester.pumpAndSettle();

      expect(find.text('내 재생목록'), findsOneWidget);
      expect(find.text('3개 선택 · 3:40'), findsOneWidget);
      expect(find.text('첫째 곡'), findsOneWidget);

      // 첫 곡을 빼면 2개가 남는다.
      await tester.tap(find.text('첫째 곡'));
      await tester.pump();
      expect(find.text('2개 선택 · 2:00'), findsOneWidget);

      // 영상으로 바꾸고 720p 를 고른다.
      await tester.tap(find.text('영상').first);
      await tester.pump();
      await tester.tap(find.text('720p'));
      await tester.pump();

      await tester.ensureVisible(find.text('대기열에 담기 (2)'));
      await tester.tap(find.text('대기열에 담기 (2)'));
      await tester.pumpAndSettle();
      expect(find.textContaining('대기열에 2개를 담았어요'), findsOneWidget);

      // 대기열 탭: 담은 두 곡이 보이고(첫 곡은 없다), 받기가 끝났다.
      await openQueueTab(tester);
      expect(find.text('둘째 곡'), findsOneWidget);
      expect(find.text('셋째 곡'), findsOneWidget);
      expect(find.text('첫째 곡'), findsNothing);
      expect(find.text('저장 완료'), findsNWidgets(2));
      expect(backend.downloaded, ['https://x/b', 'https://x/c']);
      expect(backend.optionsSeen.every((o) => o.kind == MediaKind.video && o.maxHeight == 720), isTrue);

      // 끝난 항목 지우기
      await tester.tap(find.text('끝난 항목 지우기'));
      await tester.pumpAndSettle();
      expect(find.text('둘째 곡'), findsNothing);
      expect(find.textContaining('대기열이 비어 있어요'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('$name: 영상 하나를 옵션 그대로 대기열에 담는다', (tester) async {
      final backend = await start(tester);

      await tester.enterText(find.byType(TextField), 'https://youtu.be/demo');
      await tester.tap(find.byTooltip('조회'));
      await tester.pumpAndSettle();
      expect(find.text('영상 제목'), findsWidgets);

      // M4A 를 고르고 담는다.
      await tester.ensureVisible(find.text('M4A'));
      await tester.tap(find.text('M4A'));
      await tester.pump();
      await tester.tap(find.byTooltip('대기열에 담기'));
      await tester.pumpAndSettle();
      expect(find.textContaining('대기열에 1개를 담았어요'), findsOneWidget);

      await openQueueTab(tester);
      expect(find.text('영상 제목'), findsOneWidget);
      expect(find.text('저장 완료'), findsOneWidget);
      expect(backend.downloaded, ['https://youtu.be/demo']);
      expect(backend.optionsSeen.single.audioFormat, 'm4a');
      expect(tester.takeException(), isNull);
    });
  }
}
