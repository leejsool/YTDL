// "받아 둔 소리로 기기 안에서 만들기"와 "영상 전체를 받아 자르기"를 진짜 DesktopBackend 로 검증한다.
// (앱 창은 안 띄움, 네트워크 필요. 10분짜리 영상으로 걸린 시간도 찍는다.)
//
//   flutter test integration_test/local_fast_backend_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/backend/desktop_backend.dart';
import 'package:ytdl/models.dart';

const _url = 'https://www.youtube.com/watch?v=aqz-KE-bpKQ';

void main() {
  late DesktopBackend backend;
  late Directory out;
  late MediaInfo info;
  final ffmpeg = '${Platform.environment['LOCALAPPDATA']}\\YTDL\\bin\\ffmpeg.exe';

  /// (코덱 이름, 길이 초, 태그 포함 로그)
  ({String log, double seconds}) probe(String path) {
    final r = Process.runSync(ffmpeg, ['-hide_banner', '-nostdin', '-i', path]);
    final log = '${r.stderr}';
    final m = RegExp(r'Duration: (\d+):(\d+):(\d+\.\d+)').firstMatch(log)!;
    return (
      log: log,
      seconds: int.parse(m.group(1)!) * 3600 + int.parse(m.group(2)!) * 60 + double.parse(m.group(3)!),
    );
  }

  Future<(DownloadResult, int, List<String>)> run(DownloadOptions o) async {
    final stages = <String>[];
    final sw = Stopwatch()..start();
    final r = await backend.download(_url, o.withInfo(info), (p) {
      if (stages.isEmpty || stages.last != p.stage) stages.add(p.stage);
    }, CancelToken());
    return (r, sw.elapsedMilliseconds, stages);
  }

  setUpAll(() async {
    out = Directory.systemTemp.createTempSync('ytdl_local_it_');
    SharedPreferences.setMockInitialValues({
      'saveDir': out.path,
      'lastUpdateCheck': DateTime.now().millisecondsSinceEpoch,
    });
    backend = DesktopBackend();
    await backend.prepare((_, _) {});
    info = await backend.fetchInfo(_url);
  });

  tearDownAll(() {
    if (out.existsSync()) out.deleteSync(recursive: true);
  });

  test('조회 직후 소리를 캐시 폴더에 받아 두고, 다시 부르면 그대로 쓴다', () async {
    final sw = Stopwatch()..start();
    final a = await backend.previewFull(_url, audioUrl: info.audioUrlFor('mp3'));
    final first = sw.elapsedMilliseconds;
    expect(a, startsWith(backend.audioCacheDir.path));
    expect(File(a).lengthSync(), greaterThan(1000000));
    // 앱을 다시 켠 것처럼 새 백엔드에서도 디스크에 남은 파일을 쓴다.
    final again = DesktopBackend();
    sw.reset();
    final b = await again.previewFull(_url, audioUrl: info.audioUrlFor('mp3'));
    // ignore: avoid_print
    print('소리 받기 ${first}ms (${File(a).lengthSync() ~/ 1024}KB), 다시 ${sw.elapsedMilliseconds}ms');
    expect(b, a);
    expect(sw.elapsedMilliseconds, lessThan(500));
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('mp3 4분 구간: 기기 안에서 자르고 변환한다', () async {
    final (r, ms, stages) = await run(
      const DownloadOptions(kind: MediaKind.audio, trimStart: 300, trimEnd: 540),
    );
    // ignore: avoid_print
    print('mp3 4분 구간 ${ms}ms $stages -> ${r.filePath}');
    expect(r.filePath, endsWith('(cut 5m00s-9m00s).mp3'));
    final p = probe(r.filePath!);
    expect(p.seconds, closeTo(240, 1));
    expect(p.log, contains('Big Buck Bunny'));
    expect(stages, contains('변환 중…'));
    expect(ms, lessThan(60000));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('m4a 전체: 다시 인코딩 없이 담기만 한다', () async {
    final (r, ms, _) = await run(const DownloadOptions(kind: MediaKind.audio, audioFormat: 'm4a'));
    // ignore: avoid_print
    print('m4a 전체 ${ms}ms');
    final p = probe(r.filePath!);
    expect(r.filePath, endsWith('.m4a'));
    expect(p.seconds, closeTo(info.durationSeconds, 2));
    expect(p.log, contains('Audio: aac'));
  }, timeout: const Timeout(Duration(minutes: 3)));

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
    print('opus 1분 구간+음량 ${ms}ms $stages');
    expect(r.filePath, endsWith('(vol +6dB) (cut 1m00s-2m00s).opus'));
    expect(probe(r.filePath!).seconds, closeTo(60, 1));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('자동 음량 분석이 받아 둔 소리로 빨리 끝난다', () async {
    final sw = Stopwatch()..start();
    final db = await backend.measureGain(_url, CancelToken(), remote: true);
    // ignore: avoid_print
    print('음량 분석(10분 전체) ${sw.elapsedMilliseconds}ms -> $db dB');
    expect(db.isFinite, isTrue);
    expect(sw.elapsedMilliseconds, lessThan(40000));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('영상 1분 구간: 전체를 받아 기기 안에서 자른다', () async {
    final (r, ms, stages) = await run(
      const DownloadOptions(kind: MediaKind.video, maxHeight: 720, trimStart: 60, trimEnd: 120),
    );
    // ignore: avoid_print
    print('영상 720p 1분 구간 ${ms}ms $stages');
    expect(r.filePath, endsWith('(cut 1m00s-2m00s).mp4'));
    expect(r.filePath, startsWith(out.path));
    expect(stages, contains('구간 자르는 중…'));
    final p = probe(r.filePath!);
    // 복사라서 시작이 앞쪽 키프레임으로 조금 당겨질 수 있다.
    expect(p.seconds, inInclusiveRange(59, 70));
    expect(p.log, contains('Video: h264'));
    // 작업 폴더는 남기지 않는다.
    final work = Directory('${backend.audioCacheDir.parent.path}\\work');
    expect(work.existsSync() ? work.listSync() : const [], isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
