import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/backend/backend.dart';
import 'package:ytdl/main.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/widgets/loading_stripes.dart';
import 'package:ytdl/widgets/range_preview.dart';
import 'package:ytdl/widgets/range_transport_bar.dart';
import 'package:ytdl/widgets/trim_selector.dart';

/// 접근성(시맨틱) 트리를 켠 채로 새 위젯들이 문제없이 그려지는지 본다(Windows 화면 낭독기 등에서 중요).
void main() {
  testWidgets('시맨틱을 켜고 새 위젯들 그리기 · 확대하기', (tester) async {
    final handle = tester.ensureSemantics();
    var s = 100000, e = 150000;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ListView(
              children: [
                const SizedBox(height: 40, child: LoadingStripes()),
                RangeTransportBar(
                  enabled: true,
                  playing: false,
                  onSetStart: () {},
                  onPlayStartPart: () {},
                  onPlayPause: () {},
                  onPlayEndPart: () {},
                  onSetEnd: () {},
                ),
                ZoomRangeSlider(
                  total: 600000,
                  start: s.toDouble(),
                  end: e.toDouble(),
                  minViewSpan: 10000,
                  minSelection: 100,
                  format: (t) => '${t.round()}',
                  caption: '선택',
                  onChanged: (a, b) => setState(() {
                    s = a.round();
                    e = b.round();
                  }),
                ),
                const TrimSelectorSkeleton(),
                const RangePreviewSkeleton(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 확대 -> 애니메이션 중 프레임을 여러 번 그린다(스크롤 막대가 나타남)
    await tester.tap(find.byTooltip('슬라이더 확대'));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'frame $i');
    }
    await tester.tap(find.byTooltip('슬라이더 확대'));
    await tester.pump(const Duration(milliseconds: 900));
    await tester.tap(find.byTooltip('슬라이더 축소'));
    await tester.pump(const Duration(milliseconds: 900));
    expect(tester.takeException(), isNull);
    handle.dispose();
  });

  testWidgets('시맨틱을 켠 채 탭 5개를 오가기', (tester) async {
    final handle = tester.ensureSemantics();
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(YtdlApp(backend: _FakeBackend()));
    await tester.pumpAndSettle();
    for (final label in ['대기열', '음원 편집', '영상 편집', '옵션', '다운로드', '대기열', '옵션', '음원 편집', '다운로드']) {
      await tester.tap(find.descendant(of: find.byType(NavigationBar), matching: find.text(label)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: label);
    }
    handle.dispose();
  });
}

class _FakeBackend extends Backend {
  @override
  String get saveLocationLabel => 'x';
  @override
  Future<void> prepare(SetupCallback onStatus) async {}
  @override
  Future<MediaInfo> fetchInfo(String url) async => throw UnimplementedError();
  @override
  Future<double> measureGain(String source, CancelToken token,
          {bool remote = false, double? startSec, double? endSec}) async =>
      0;
  @override
  Future<DownloadResult> download(String url, DownloadOptions options,
          void Function(DownloadProgress) onProgress, CancelToken token) async =>
      throw UnimplementedError();
  @override
  Future<DownloadResult> trimAudio(String srcPath, double startSec, double endSec, String outBaseName,
          {AudioGain gain = const AudioGain.none()}) async =>
      throw UnimplementedError();
  @override
  Future<String> updateEngine() async => '';
}
