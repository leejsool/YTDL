// 진짜 DesktopBackend 로 새 기능을 검증한다(앱 창은 안 띄움, 네트워크 필요).
//  - 미리듣기: 조회에서 얻은 소리 주소를 10MB 씩 나눠 받아 구간을 잘라 wav 로 만들기(+ 음량 적용)
//  - 영상 자르기: 복사(빠르게) / 다시 인코딩(정확하게)
//
//   flutter test integration_test/preview_video_backend_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/backend/desktop_backend.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/util/preview_renderer.dart';

const _url = 'https://www.youtube.com/watch?v=jNQXAC9IVRw';

void main() {
  late DesktopBackend backend;
  late Directory out;
  late String ffmpeg;

  setUpAll(() async {
    out = Directory.systemTemp.createTempSync('ytdl_pv_it_');
    SharedPreferences.setMockInitialValues({
      'saveDir': out.path,
      'lastUpdateCheck': DateTime.now().millisecondsSinceEpoch,
    });
    backend = DesktopBackend();
    await backend.prepare((_, _) {});
    ffmpeg = '${Platform.environment['LOCALAPPDATA']}\\YTDL\\bin\\ffmpeg.exe';
  });

  tearDownAll(() {
    if (out.existsSync()) out.deleteSync(recursive: true);
  });

  double duration(String path) {
    final r = Process.runSync(ffmpeg, ['-hide_banner', '-nostdin', '-i', path]);
    final m = RegExp(r'Duration: (\d+):(\d+):(\d+\.\d+)').firstMatch('${r.stderr}')!;
    return int.parse(m.group(1)!) * 3600 + int.parse(m.group(2)!) * 60 + double.parse(m.group(3)!);
  }

  test('미리듣기: 주소를 나눠 받아 구간을 wav 로, 음량 적용도', () async {
    final info = await backend.fetchInfo(_url);
    expect(info.previewAudioUrl, isNotNull);
    final renderer = PreviewRenderer(backend);

    final sw = Stopwatch()..start();
    final plain = await renderer.render(info.url, 3, 9, const AudioGain.none(), audioUrl: info.previewAudioUrl);
    final first = sw.elapsedMilliseconds;
    expect(File(plain).existsSync(), isTrue);
    expect(plain, endsWith('.wav'));
    expect(duration(plain), closeTo(6, 0.5));

    sw.reset();
    final boosted = await renderer.render(info.url, 3, 9, const AudioGain.manual(12), audioUrl: info.previewAudioUrl);
    final second = sw.elapsedMilliseconds;
    expect(boosted, isNot(plain));
    expect(duration(boosted), closeTo(6, 0.5));
    // ignore: avoid_print
    print('처음 ${first}ms, 같은 영상 다른 음량 ${second}ms');
  });

  group('영상 자르기', () {
    late String src;

    setUpAll(() {
      src = '${out.path}\\src.mp4';
      final r = Process.runSync(ffmpeg, [
        '-nostdin', '-y', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'testsrc=size=320x180:rate=30',
        '-f', 'lavfi', '-i', 'sine=frequency=440',
        '-t', '30', '-c:v', 'libx264', '-g', '60', '-pix_fmt', 'yuv420p', '-c:a', 'aac', src,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
    });

    test('빠르게(복사): 원본 형식 그대로, 키프레임 단위', () async {
      final r = await backend.trimVideo(src, 10, 18, 'copy test');
      expect(File(r.filePath!).existsSync(), isTrue);
      expect(r.filePath, endsWith('.mp4'));
      expect(duration(r.filePath!), closeTo(8, 2.5));
    });

    test('정확하게(다시 인코딩): 정확한 길이의 mp4', () async {
      final r = await backend.trimVideo(src, 10, 18, 'reenc test', reencode: true);
      expect(File(r.filePath!).existsSync(), isTrue);
      expect(r.filePath, endsWith('.mp4'));
      expect(duration(r.filePath!), closeTo(8, 0.3));
    });
  });
}
