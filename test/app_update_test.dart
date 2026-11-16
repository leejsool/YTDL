import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:ytdl/backend/backend.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/util/app_update.dart';
import 'package:ytdl/widgets/app_update_panel.dart';

Map<String, dynamic> _release(String tag, List<String> names) => {
  'tag_name': tag,
  'body': '고친 점',
  'assets': [
    for (final n in names)
      {
        'name': n,
        'browser_download_url': 'https://example.com/$n',
        'size': 1048576,
      },
  ],
};

const _all = [
  'YTDL-1.0.1-android-arm64.apk',
  'YTDL-1.0.1-android-armv7.apk',
  'YTDL-1.0.1-windows-x64.zip',
  'YTDL-1.0.1-windows-setup.exe',
];

void main() {
  test('버전 비교', () {
    expect(compareVersions('v1.0.1', '1.0.0'), greaterThan(0));
    expect(compareVersions('1.0.0', '1.0.0+5'), 0);
    expect(compareVersions('1.10.0', '1.9.9'), greaterThan(0));
    expect(compareVersions('1.0', '1.0.0'), 0);
    expect(compareVersions('0.9.9', '1.0.0'), lessThan(0));
  });

  test('기기에 맞는 설치 파일 고르기', () {
    final assets = [
      for (final n in _all)
        UpdateAsset(name: n, url: 'https://x/$n', size: 1),
    ];
    expect(
      AppUpdater.pickAsset(assets, android: true, abi: 'arm64-v8a')?.name,
      'YTDL-1.0.1-android-arm64.apk',
    );
    expect(
      AppUpdater.pickAsset(assets, android: true, abi: 'armeabi-v7a')?.name,
      'YTDL-1.0.1-android-armv7.apk',
    );
    expect(AppUpdater.pickAsset(assets, android: true, abi: 'x86_64'), isNull);
    expect(
      AppUpdater.pickAsset(assets, android: false)?.name,
      'YTDL-1.0.1-windows-setup.exe',
    );
  });

  test('새 버전이 없으면 null, 있으면 정보', () async {
    final same = AppUpdater(fetchJson: (_) async => _release('v1.0.0', _all));
    expect(
      await same.checkLatest(currentVersion: '1.0.0', android: false),
      isNull,
    );
    final newer = AppUpdater(fetchJson: (_) async => _release('v1.0.1', _all));
    final info = await newer.checkLatest(
      currentVersion: '1.0.0',
      android: false,
    );
    expect(info?.version, '1.0.1');
    expect(info?.asset.name, 'YTDL-1.0.1-windows-setup.exe');
    expect(info?.notes, '고친 점');
  });

  test('맞는 설치 파일이 없으면 안내 오류', () {
    final u = AppUpdater(
      fetchJson: (_) async => _release('v1.0.1', ['notes.txt']),
    );
    expect(
      u.checkLatest(currentVersion: '1.0.0', android: false),
      throwsA(isA<UpdateException>()),
    );
  });

  group('옵션 탭 업데이트 패널', () {
    setUp(() {
      PackageInfo.setMockInitialValues(
        appName: 'ytdl',
        packageName: 'com.ytdl.ytdl',
        version: '1.0.0',
        buildNumber: '1',
        buildSignature: '',
      );
    });

    Future<void> pump(WidgetTester t, AppUpdater updater) async {
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppUpdatePanel(backend: _Fake(), updater: updater),
          ),
        ),
      );
      await t.pumpAndSettle();
    }

    testWidgets('현재 버전을 보여 주고 최신이면 안내한다', (t) async {
      await pump(t, AppUpdater(fetchJson: (_) async => _release('v1.0.0', _all)));
      expect(find.text('v1.0.0'), findsOneWidget);
      await t.tap(find.text('업데이트 확인'));
      await t.pumpAndSettle();
      expect(find.text('최신 버전이에요.'), findsOneWidget);
    });

    testWidgets('새 버전이 있으면 업데이트 버튼이 나온다', (t) async {
      await pump(t, AppUpdater(fetchJson: (_) async => _release('v1.0.1', _all)));
      await t.tap(find.text('업데이트 확인'));
      await t.pumpAndSettle();
      expect(find.textContaining('v1.0.1'), findsOneWidget);
      expect(find.text('업데이트'), findsOneWidget);
    });

    testWidgets('확인 실패는 오류 문구로 보인다', (t) async {
      await pump(
        t,
        AppUpdater(fetchJson: (_) async => throw UpdateException('연결 실패')),
      );
      await t.tap(find.text('업데이트 확인'));
      await t.pumpAndSettle();
      expect(find.text('연결 실패'), findsOneWidget);
    });
  });
}

class _Fake extends Backend {
  @override
  bool get canSelfUpdate => true;

  @override
  String get saveLocationLabel => '';

  @override
  Future<void> prepare(SetupCallback onStatus) async {}

  @override
  Future<MediaInfo> fetchInfo(String url) => throw UnimplementedError();

  @override
  Future<DownloadResult> download(
    String url,
    DownloadOptions options,
    void Function(DownloadProgress) onProgress,
    CancelToken token,
  ) async => throw UnimplementedError();

  @override
  Future<double> measureGain(
    String source,
    CancelToken token, {
    bool remote = false,
    double? startSec,
    double? endSec,
  }) async => throw UnimplementedError();

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
