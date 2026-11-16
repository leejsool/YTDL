// "받아 둔 소리로 폰 안에서 만들기"와 "영상 전체를 받아 자르기"를 실제 Android 기기에서 검증한다.
// (네트워크 필요. 결과 파일은 Music/YTDL, Movies/YTDL 에 남는다.)
//
//   flutter test integration_test/local_fast_android_test.dart -d <기기>
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:ytdl/backend/android_backend.dart';
import 'package:ytdl/models.dart';

const _url = 'https://www.youtube.com/watch?v=aqz-KE-bpKQ';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late AndroidBackend backend;
  late MediaInfo info;

  Future<(DownloadResult, int, List<String>)> run(DownloadOptions o) async {
    final stages = <String>[];
    final sw = Stopwatch()..start();
    final r = await backend.download(_url, o.withInfo(info), (p) {
      if (stages.isEmpty || stages.last != p.stage) stages.add(p.stage);
    }, CancelToken());
    return (r, sw.elapsedMilliseconds, stages);
  }

  setUpAll(() async {
    backend = AndroidBackend();
    await backend.prepare((_, _) {});
    final sw = Stopwatch()..start();
    info = await backend.fetchInfo(_url);
    // ignore: avoid_print
    print('RESULT 조회 ${sw.elapsedMilliseconds}ms');
  });

  test('소리를 캐시 폴더에 받아 둔다', () async {
    final sw = Stopwatch()..start();
    final a = await backend.previewFull(_url, audioUrl: info.audioUrlFor('mp3'));
    // ignore: avoid_print
    print('RESULT 소리 받기 ${sw.elapsedMilliseconds}ms ${File(a).lengthSync() ~/ 1024}KB $a');
    expect(a, startsWith(backend.audioCacheDir.path));
    expect(File(a).lengthSync(), greaterThan(1000000));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('mp3 4분 구간', () async {
    final (r, ms, stages) = await run(
      const DownloadOptions(kind: MediaKind.audio, trimStart: 300, trimEnd: 540),
    );
    // ignore: avoid_print
    print('RESULT mp3 4분 구간 ${ms}ms $stages -> ${r.location}');
    expect(r.location, contains('(cut 5m00s-9m00s)'));
    expect(r.location, endsWith('.mp3'));
    expect(stages, contains('변환 중…'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('m4a 전체(담기만)', () async {
    final (r, ms, stages) = await run(
      const DownloadOptions(kind: MediaKind.audio, audioFormat: 'm4a'),
    );
    // ignore: avoid_print
    print('RESULT m4a 전체 ${ms}ms $stages -> ${r.location}');
    expect(r.location, endsWith('.m4a'));
    expect(stages, contains('변환 중…'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('opus 1분 구간 + 음량 +6dB', () async {
    final (r, ms, stages) = await run(
      const DownloadOptions(
        kind: MediaKind.audio,
        audioFormat: 'opus',
        trimStart: 60,
        trimEnd: 120,
        gain: AudioGain.manual(6),
      ),
    );
    // ignore: avoid_print
    print('RESULT opus 1분+음량 ${ms}ms $stages -> ${r.location}');
    expect(r.location, endsWith('.opus'));
    expect(stages, contains('음량 조절 중…'));
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('자동 음량 분석(10분 전체)', () async {
    final sw = Stopwatch()..start();
    final db = await backend.measureGain(_url, CancelToken(), remote: true);
    // ignore: avoid_print
    print('RESULT 음량 분석 ${sw.elapsedMilliseconds}ms -> $db dB');
    expect(db.isFinite, isTrue);
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('영상 720p 1분 구간: 전체를 받아 자른다', () async {
    final (r, ms, stages) = await run(
      const DownloadOptions(kind: MediaKind.video, maxHeight: 720, trimStart: 60, trimEnd: 120),
    );
    // ignore: avoid_print
    print('RESULT 영상 720p 1분 구간 ${ms}ms $stages -> ${r.location}');
    expect(r.location, endsWith('.mp4'));
    expect(stages, contains('구간 자르는 중…'));
  }, timeout: const Timeout(Duration(minutes: 10)));
}
