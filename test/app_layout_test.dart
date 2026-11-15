import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/backend/backend.dart';
import 'package:ytdl/main.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/widgets/gain_selector.dart';

class _PreviewBackend extends Backend {
  (double?, double?)? analyzedRange;

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
  Future<double> measureGain(
    String source,
    CancelToken token, {
    bool remote = false,
    double? startSec,
    double? endSec,
  }) async {
    expect(remote, isTrue);
    analyzedRange = (startSec, endSec);
    return 8.4;
  }

  @override
  Future<DownloadResult> download(
    String url,
    DownloadOptions options,
    void Function(DownloadProgress) onProgress,
    CancelToken token,
  ) async => throw UnimplementedError();

  @override
  Future<DownloadResult> trimAudio(
    String srcPath,
    double startSec,
    double endSec,
    String outBaseName, {
    AudioGain gain = const AudioGain.none(),
  }) async => throw UnimplementedError();

  @override
  Future<String> updateEngine() async => '완료';
}

void main() {
  for (final wide in [true, false]) {
    testWidgets(
      '${wide ? 'wide' : 'mobile'} layout loads the media, range and gain controls',
      (tester) async {
        final semantics = tester.ensureSemantics();
        SharedPreferences.setMockInitialValues({});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = wide
            ? const Size(1200, 850)
            : const Size(320, 760);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final backend = _PreviewBackend();
        await tester.pumpWidget(YtdlApp(backend: backend));
        await tester.pumpAndSettle();

        expect(
          find.byType(NavigationBar),
          wide ? findsNothing : findsOneWidget,
        );
        expect(find.text('저장할 영상 링크를 입력하세요'), findsOneWidget);
        await tester.enterText(find.byType(TextField), 'https://youtu.be/demo');
        await tester.tap(find.byTooltip('조회'));
        await tester.pumpAndSettle();
        final title = tester.getRect(find.text('영상 제목'));
        final options = tester.getRect(find.text('저장 옵션'));
        expect(
          wide ? title.right < options.left : title.bottom < options.top,
          isTrue,
        );

        final trim = find.text('구간 자르기');
        await tester.ensureVisible(trim);
        await tester.tap(trim);
        await tester.pumpAndSettle();
        expect(find.byType(RangeSlider), findsOneWidget);

        final end = find.widgetWithText(TextField, '끝');
        await tester.ensureVisible(end);
        await tester.enterText(end, '0:24');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.text('잘라낼 길이 0:24  (전체 1:22)'), findsOneWidget);

        // 음량 조절은 기본으로 접혀 있으니 펼친다.
        await tester.ensureVisible(find.text('음량 조절'));
        await tester.tap(find.text('음량 조절'));
        await tester.pumpAndSettle();
        final gain = find.byType(GainSelector);
        await tester.ensureVisible(gain);
        expect(
          find.descendant(of: gain, matching: find.text('+0')),
          findsOneWidget,
        );
        final automatic = find.text('자동');
        await tester.ensureVisible(automatic);
        await tester.tap(automatic);
        await tester.pumpAndSettle();
        expect(backend.analyzedRange, (0.0, 24.0));
        expect(
          find.descendant(of: gain, matching: find.text('+8')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        semantics.dispose();
      },
    );
  }
}
