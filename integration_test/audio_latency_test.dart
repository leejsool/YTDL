// 첫 재생 버벅임 측정: 재생 시작 후 "실제 경과 시간 - 재생 위치" (= 소리가 늦는 정도)를 잰다.
// 갓 로드한 플레이어(cold)와, 소리 없이 한 번 돌려 준비시킨 플레이어(primed)를 비교한다.
//
//   flutter test integration_test/audio_latency_test.dart -d windows
//   (재생할 mp3 경로는 환경변수 LATENCY_FILE, 없으면 아래 기본값)
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

// Android 는 앱 전용 폴더(권한 없이 읽을 수 있음)에 adb push 로 넣어 둔다:
//   adb push latency_sample.mp3 /sdcard/Android/data/com.ytdl.ytdl/files/latency_sample.mp3
final _defaultFile = Platform.isAndroid
    ? '/sdcard/Android/data/com.ytdl.ytdl/files/latency_sample.mp3'
    : r'C:\myapp\tmp\latency_sample.mp3';

class Sample {
  Sample(this.elapsedMs, this.posMs);
  final int elapsedMs;
  final int posMs;
}

Future<void> wait(WidgetTester t, int ms) async {
  final sw = Stopwatch()..start();
  while (sw.elapsedMilliseconds < ms) {
    await t.pump(const Duration(milliseconds: 10));
  }
}

/// resume() 호출 시점부터 [ms] 동안 (경과, 위치) 를 모은다.
Future<List<Sample>> record(WidgetTester t, AudioPlayer p, {int ms = 1500}) async {
  final out = <Sample>[];
  final sw = Stopwatch();
  final sub = p.onPositionChanged.listen((d) {
    if (sw.isRunning) out.add(Sample(sw.elapsedMilliseconds, d.inMilliseconds));
  });
  sw.start();
  await p.resume();
  await wait(t, ms);
  await sub.cancel();
  return out;
}

/// 경과 시간 [atMs] 시점의 지연(ms): 경과 - 위치. 클수록 소리가 늦게 시작했다는 뜻.
int lagAt(List<Sample> s, int atMs) {
  Sample? last;
  for (final x in s) {
    if (x.elapsedMs <= atMs) last = x;
  }
  return last == null ? atMs : last.elapsedMs - last.posMs;
}

/// 위치가 처음으로 50ms 를 넘기까지 걸린 실제 시간.
int firstSound(List<Sample> s) {
  for (final x in s) {
    if (x.posMs >= 50) return x.elapsedMs - x.posMs; // 시작이 늦은 만큼
  }
  return 9999;
}

String describe(String name, List<List<Sample>> runs) {
  final lag = runs.map((r) => lagAt(r, 1000)).toList();
  final first = runs.map(firstSound).toList();
  return '$name  | 1초 시점 지연(ms): $lag  | 소리 시작 지연(ms): $first';
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('첫 재생 지연: cold vs primed', (t) async {
    final path = Platform.environment['LATENCY_FILE'] ?? _defaultFile;
    expect(File(path).existsSync(), isTrue, reason: '샘플 파일 필요: $path');

    final cold = <List<Sample>>[];
    final second = <List<Sample>>[];
    final primed = <List<Sample>>[];

    for (var i = 0; i < 3; i++) {
      // A) 갓 로드한 플레이어의 첫 재생
      final a = AudioPlayer();
      await a.setReleaseMode(ReleaseMode.stop);
      await a.setSource(DeviceFileSource(path));
      await wait(t, 600); // 로드 끝나고 사용자가 누르기까지의 여유
      cold.add(await record(t, a));

      // B) 같은 플레이어의 두 번째 재생
      await a.pause();
      await a.seek(Duration.zero);
      await wait(t, 300);
      second.add(await record(t, a));
      await a.dispose();

      // C) 준비운동(소리 0으로 잠깐 재생 -> 정지 -> 처음으로) 후 첫 재생
      final b = AudioPlayer();
      await b.setReleaseMode(ReleaseMode.stop);
      await b.setSource(DeviceFileSource(path));
      await b.setVolume(0);
      await b.resume();
      await wait(t, 300);
      await b.pause();
      await b.seek(Duration.zero);
      await b.setVolume(1);
      await wait(t, 600);
      primed.add(await record(t, b));
      await b.dispose();
    }

    // ignore: avoid_print
    print('\n[LATENCY] ${describe('cold   (첫 재생)', cold)}'
        '\n[LATENCY] ${describe('second (두 번째)', second)}'
        '\n[LATENCY] ${describe('primed (준비 후 첫 재생)', primed)}\n');
  });
}
