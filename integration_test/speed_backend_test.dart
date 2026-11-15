// 속도 개선(조회 결과 재사용, 폴더형 yt-dlp, 받아 둔 소리로 음량 분석)을 진짜 DesktopBackend 로 검증한다.
// (앱 창은 안 띄움, 네트워크 필요)
//
//   flutter test integration_test/speed_backend_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/backend/desktop_backend.dart';
import 'package:ytdl/models.dart';

const _url = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';

void main() {
  late DesktopBackend backend;
  late Directory out;
  late MediaInfo info;

  setUpAll(() async {
    out = Directory.systemTemp.createTempSync('ytdl_speed_it_');
    SharedPreferences.setMockInitialValues({
      'saveDir': out.path,
      'lastUpdateCheck': DateTime.now().millisecondsSinceEpoch,
    });
    backend = DesktopBackend();
    await backend.prepare((_, _) {});
  });

  tearDownAll(() {
    if (out.existsSync()) out.deleteSync(recursive: true);
  });

  test('폴더형 yt-dlp 가 설치돼 있다', () {
    final bin = '${Platform.environment['LOCALAPPDATA']}\\YTDL\\bin';
    expect(File('$bin\\ytdlp\\yt-dlp.exe').existsSync(), isTrue);
    expect(Directory('$bin\\ytdlp\\_internal').existsSync(), isTrue);
  });

  test('조회가 JSON 원문과 소리 주소를 돌려준다', () async {
    final sw = Stopwatch()..start();
    info = await backend.fetchInfo(_url);
    // ignore: avoid_print
    print('조회 ${sw.elapsedMilliseconds}ms, JSON ${info.rawJson!.length ~/ 1024}KB');
    expect(info.reusableJson, isNotNull);
    expect(info.previewAudioUrl, isNotNull);
    expect(info.durationSeconds, greaterThan(10));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('조회 결과로 받으면 일반 다운로드와 같은 파일이 나오고 더 빠르다', () async {
    final dirA = Directory('${out.path}\\a')..createSync();
    final dirB = Directory('${out.path}\\b')..createSync();
    // 저장 폴더를 바꿔 가며 같은 이름이 겹치지 않게 받는다.
    SharedPreferences.setMockInitialValues({'saveDir': dirA.path});
    final a = DesktopBackend();
    await a.prepare((_, _) {});
    SharedPreferences.setMockInitialValues({'saveDir': dirB.path});
    final b = DesktopBackend();
    await b.prepare((_, _) {});

    const base = DownloadOptions(kind: MediaKind.audio, trimStart: 2, trimEnd: 8);
    final swA = Stopwatch()..start();
    final plain = await a.download(_url, base, (_) {}, CancelToken());
    final tPlain = swA.elapsedMilliseconds;

    final fast = DownloadOptions(
      kind: MediaKind.audio,
      trimStart: 2,
      trimEnd: 8,
      infoJson: info.reusableJson,
    );
    final swB = Stopwatch()..start();
    final viaInfo = await b.download(_url, fast, (_) {}, CancelToken());
    final tInfo = swB.elapsedMilliseconds;
    // ignore: avoid_print
    print('일반 ${tPlain}ms / 조회 결과 재사용 ${tInfo}ms');

    expect(File(viaInfo.filePath!).existsSync(), isTrue);
    expect(
      (File(viaInfo.filePath!).lengthSync() - File(plain.filePath!).lengthSync()).abs(),
      lessThan(2000),
    );
    expect(tInfo, lessThan(tPlain));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('JSON 이 쓸모없어도 주소로 다시 받아서 성공한다', () async {
    final dir = Directory('${out.path}\\c')..createSync();
    SharedPreferences.setMockInitialValues({'saveDir': dir.path});
    final c = DesktopBackend();
    await c.prepare((_, _) {});
    final r = await c.download(
      _url,
      const DownloadOptions(
        kind: MediaKind.audio,
        trimStart: 2,
        trimEnd: 6,
        infoJson: '{"not":"a real info json"}',
      ),
      (_) {},
      CancelToken(),
    );
    expect(File(r.filePath!).existsSync(), isTrue);
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('영상 구간 다운로드도 조회 결과로 받아진다', () async {
    final dir = Directory('${out.path}\\v')..createSync();
    SharedPreferences.setMockInitialValues({'saveDir': dir.path});
    final v = DesktopBackend();
    await v.prepare((_, _) {});
    final r = await v.download(
      _url,
      DownloadOptions(
        kind: MediaKind.video,
        maxHeight: 360,
        trimStart: 3,
        trimEnd: 9,
        infoJson: info.reusableJson,
      ),
      (_) {},
      CancelToken(),
    );
    expect(r.filePath, endsWith('.mp4'));
    expect(File(r.filePath!).lengthSync(), greaterThan(10000));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('받아 둔 소리가 있으면 음량 분석이 그걸로 빠르게 끝난다', () async {
    final fresh = DesktopBackend();
    SharedPreferences.setMockInitialValues({'saveDir': out.path});
    await fresh.prepare((_, _) {});

    final swSlow = Stopwatch()..start();
    final slow = await fresh.measureGain(_url, CancelToken(),
        remote: true, startSec: 2, endSec: 12);
    final tSlow = swSlow.elapsedMilliseconds;

    await fresh.previewFull(_url, audioUrl: info.previewAudioUrl);
    expect(await fresh.cachedFullAudio(_url), isNotNull);
    final swFast = Stopwatch()..start();
    final fast = await fresh.measureGain(_url, CancelToken(),
        remote: true, startSec: 2, endSec: 12);
    final tFast = swFast.elapsedMilliseconds;
    // ignore: avoid_print
    print('음량 분석: yt-dlp ${tSlow}ms ($slow dB) / 받아 둔 소리 ${tFast}ms ($fast dB)');

    expect(fast.isFinite, isTrue);
    expect((fast - slow).abs(), lessThan(1.5));
    expect(tFast, lessThan(tSlow));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
