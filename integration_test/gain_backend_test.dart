// 진짜 DesktopBackend 로 음량 조절을 검증한다(앱 창은 안 띄움, 네트워크 필요).
//  - 다운로드 때 음량 조절(이미 목표 형식인 m4a 도 포함: yt-dlp 단독으로는 필터가 무시되던 경우)
//  - 이미 받은 파일을 자르면서 음량 조절
//
//   flutter test integration_test/gain_backend_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/backend/desktop_backend.dart';
import 'package:ytdl/models.dart';

const _url = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';

void main() {
  late DesktopBackend backend;
  late Directory out;
  late String ffmpeg;

  setUpAll(() async {
    out = Directory.systemTemp.createTempSync('ytdl_gain_it_');
    SharedPreferences.setMockInitialValues({
      'saveDir': out.path,
      'lastUpdateCheck': DateTime.now().millisecondsSinceEpoch, // 엔진 업데이트 확인은 건너뜀
    });
    backend = DesktopBackend();
    await backend.prepare((_, _) {});
    ffmpeg = '${Platform.environment['LOCALAPPDATA']}\\YTDL\\bin\\ffmpeg.exe';
  });

  tearDownAll(() {
    if (out.existsSync()) out.deleteSync(recursive: true);
  });

  double meanVolume(String path) {
    final r = Process.runSync(
        ffmpeg, ['-hide_banner', '-nostdin', '-i', path, '-af', 'volumedetect', '-f', 'null', 'NUL']);
    return double.parse(RegExp(r'mean_volume: (-?[0-9.]+) dB').firstMatch('${r.stderr}')!.group(1)!);
  }

  Future<DownloadResult> dl(DownloadOptions o) =>
      backend.download(_url, o, (_) {}, CancelToken());

  test('M4A 구간 다운로드 + 12dB (yt-dlp 가 필터를 무시하던 경우)', () async {
    // 같은 조건으로 음량만 다르게 받아 비교한다.
    final base = await dl(const DownloadOptions(
        kind: MediaKind.audio, audioFormat: 'm4a', trimStart: 2, trimEnd: 8));
    final boosted = await dl(const DownloadOptions(
        kind: MediaKind.audio,
        audioFormat: 'm4a',
        trimStart: 2,
        trimEnd: 8,
        gain: AudioGain.manual(12)));

    expect(boosted.filePath, endsWith('(vol +12dB) (cut 0m02s-0m08s).m4a'));
    expect(File(boosted.filePath!).existsSync(), isTrue);
    expect(out.listSync().map((e) => e.path).where((p) => p.contains('.gain.')), isEmpty,
        reason: '임시 파일이 남지 않는다');
    final diff = meanVolume(boosted.filePath!) - meanVolume(base.filePath!);
    expect(diff, closeTo(12, 3), reason: '평균 음량이 약 12dB 커짐(리미터로 일부 깎일 수 있음): $diff');
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('MP3 다운로드 + 자동 맞춤', () async {
    final r = await dl(const DownloadOptions(
        kind: MediaKind.audio, trimStart: 2, trimEnd: 8, gain: AudioGain.auto()));
    expect(r.filePath, endsWith('(vol auto) (cut 0m02s-0m08s).mp3'));
    expect(File(r.filePath!).lengthSync(), greaterThan(10000));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('받은 파일을 자르면서 음량 조절(trimAudio), 음량 없으면 그대로 복사', () async {
    final src = await dl(const DownloadOptions(kind: MediaKind.audio, trimStart: 0, trimEnd: 10));
    final before = meanVolume(src.filePath!);

    final copied = await backend.trimAudio(src.filePath!, 1, 4, 'copy only');
    expect(meanVolume(copied.filePath!), closeTo(before, 1.5));

    final boosted = await backend.trimAudio(src.filePath!, 1, 4, 'boosted (vol +9dB)',
        gain: const AudioGain.manual(9));
    expect(boosted.filePath, endsWith('boosted (vol +9dB).mp3'));
    expect(meanVolume(boosted.filePath!) - before, closeTo(9, 3));
    expect(File(src.filePath!).existsSync(), isTrue, reason: '원본은 그대로');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
