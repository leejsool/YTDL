import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytdl/backend/gain_args.dart';
import 'package:ytdl/backend/ytdlp_args.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/util/names.dart';

void main() {
  group('AudioGain', () {
    test('조절 없음 / 0dB 는 비활성', () {
      expect(const AudioGain.none().isActive, isFalse);
      expect(const AudioGain.manual(0).isActive, isFalse);
      expect(const AudioGain.manual(6).isActive, isTrue);
      expect(const AudioGain.auto().isActive, isTrue);
    });

    test('파일 이름 표시', () {
      expect(const AudioGain.none().nameTag, '');
      expect(const AudioGain.manual(0).nameTag, '');
      expect(const AudioGain.manual(6).nameTag, ' (vol +6dB)');
      expect(const AudioGain.manual(-3).nameTag, ' (vol -3dB)');
      expect(const AudioGain.auto().nameTag, ' (vol auto)');
    });

    test('음량 표시가 있어도 (cut …) 이름을 그대로 해석한다', () {
      final name = 'Song${const AudioGain.manual(6).nameTag}${cutSuffix(5, 12)}';
      expect(name, 'Song (vol +6dB) (cut 0m05s-0m12s)');
      expect(parseCutTag(name), (start: 5.0, end: 12.0));
      expect(stripCut(name), 'Song (vol +6dB)');
    });
  });

  group('gainFilter / gainEncodeArgs', () {
    test('조절 없으면 null (= -c copy 를 쓴다)', () {
      expect(gainFilter(const AudioGain.none()), isNull);
      expect(gainEncodeArgs(const AudioGain.none(), 'mp3'), isNull);
      expect(gainEncodeArgs(const AudioGain.manual(0), 'mp3'), isNull);
    });

    test('키울 때는 클리핑 방지 리미터가 붙고, 줄일 때는 붙지 않는다', () {
      expect(gainFilter(const AudioGain.manual(6)), 'volume=6.0dB,alimiter=limit=0.97:level=0');
      expect(gainFilter(const AudioGain.manual(-3)), 'volume=-3.0dB');
      expect(gainFilter(const AudioGain.auto()), startsWith('loudnorm='));
    });

    test('형식별 인코더', () {
      List<String> a(String ext) => gainEncodeArgs(const AudioGain.manual(6), ext)!;
      expect(a('mp3'), containsAllInOrder(['-c:a', 'libmp3lame']));
      expect(a('m4a'), containsAllInOrder(['-c:a', 'aac']));
      expect(a('opus'), containsAllInOrder(['-c:a', 'libopus']));
      // 앨범 그림은 mp3/m4a/flac 만 가져간다.
      expect(a('mp3'), contains('0:v?'));
      expect(a('opus'), isNot(contains('0:v?')));
      expect(a('mp3'), containsAllInOrder(['-af', 'volume=6.0dB,alimiter=limit=0.97:level=0']));
    });
  });

  group('다운로드 인자', () {
    String outputTemplate(DownloadOptions o) {
      final args = buildDownloadArgs(o);
      return args[args.indexOf('-o') + 1];
    }

    test('음원에는 음량 표시를 이름에 붙이고, 구간 표시보다 앞에 둔다', () {
      expect(outputTemplate(const DownloadOptions(kind: MediaKind.audio)), '%(title).100s.%(ext)s');
      expect(
        outputTemplate(const DownloadOptions(kind: MediaKind.audio, gain: AudioGain.manual(6))),
        '%(title).100s (vol +6dB).%(ext)s',
      );
      expect(
        outputTemplate(const DownloadOptions(
            kind: MediaKind.audio, gain: AudioGain.auto(), trimStart: 5, trimEnd: 12)),
        '%(title).100s (vol auto) (cut 0m05s-0m12s).%(ext)s',
      );
    });

    test('영상은 음량 설정을 무시한다', () {
      expect(
        outputTemplate(const DownloadOptions(kind: MediaKind.video, gain: AudioGain.manual(6))),
        '%(title).100s.%(ext)s',
      );
    });

    test('음량은 yt-dlp 가 아니라 ffmpeg 로 따로 처리한다(yt-dlp 인자에는 필터가 없다)', () {
      final args = buildDownloadArgs(
          const DownloadOptions(kind: MediaKind.audio, gain: AudioGain.manual(6)));
      expect(args.join(' '), isNot(contains('volume')));
      expect(args, isNot(contains('--postprocessor-args')));
    });
  });

  test('Android 가 보내는 음량 조절 시작 줄을 진행 상태로 해석', () {
    expect(ProgressParser().parse(gainMarker)?.stage, '음량 조절 중…');
  });

  // 실제 ffmpeg 로 확인(도구 폴더가 없는 PC 에서는 건너뜀).
  group('실제 ffmpeg 로 음량이 바뀌는지', () {
    const toolsDir = r'C:\myapp\tools\ytdlp';
    final ffmpeg = '$toolsDir\\ffmpeg.exe';
    final have = Platform.isWindows && File(ffmpeg).existsSync();

    late Directory dir;
    setUpAll(() {
      if (!have) return;
      dir = Directory.systemTemp.createTempSync('ytdl_gain_');
    });
    tearDownAll(() {
      if (have && dir.existsSync()) dir.deleteSync(recursive: true);
    });

    /// 사인파 3초(작은 소리, 약 -26 dBFS)를 [ext] 형식으로 만든다.
    String makeQuiet(String ext) {
      final out = '${dir.path}\\quiet.$ext';
      final r = Process.runSync(ffmpeg, [
        '-nostdin', '-y', '-loglevel', 'error',
        '-f', 'lavfi', '-i', 'sine=frequency=440:duration=3',
        '-af', 'volume=0.05',
        out,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      return out;
    }

    ({double mean, double max}) levels(String path) {
      final r = Process.runSync(
          ffmpeg, ['-hide_banner', '-nostdin', '-i', path, '-af', 'volumedetect', '-f', 'null', 'NUL']);
      final text = '${r.stderr}';
      double pick(String key) =>
          double.parse(RegExp('$key: (-?[0-9.]+) dB').firstMatch(text)!.group(1)!);
      return (mean: pick('mean_volume'), max: pick('max_volume'));
    }

    for (final ext in ['mp3', 'm4a', 'opus', 'flac', 'wav']) {
      test('+12dB: $ext', () {
        final src = makeQuiet(ext);
        final out = '${dir.path}\\boost.$ext';
        final enc = gainEncodeArgs(const AudioGain.manual(12), ext)!;
        final r = Process.runSync(ffmpeg, [
          '-nostdin', '-y', '-loglevel', 'error',
          '-i', src, '-ss', '0.500', '-t', '2.000', '-map_metadata', '0',
          ...enc,
          out,
        ]);
        expect(r.exitCode, 0, reason: '${r.stderr}');
        final before = levels(src);
        final after = levels(out);
        // 약 12dB 커졌고(코덱 오차 감안), 최대치(0 dB)를 넘지 않는다.
        expect(after.mean - before.mean, closeTo(12, 1.5));
        expect(after.max, lessThan(0.01));
      }, skip: have ? false : 'ffmpeg 없음');
    }

    test('자동: 작은 소리가 커진다', () {
      final src = makeQuiet('mp3');
      final out = '${dir.path}\\auto.mp3';
      final r = Process.runSync(ffmpeg, [
        '-nostdin', '-y', '-loglevel', 'error', '-i', src,
        ...gainEncodeArgs(const AudioGain.auto(), 'mp3')!,
        out,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(levels(out).mean, greaterThan(levels(src).mean + 3));
    }, skip: have ? false : 'ffmpeg 없음');

    test('많이 키워도 클리핑하지 않는다(+20dB)', () {
      final src = makeQuiet('wav');
      final out = '${dir.path}\\loud.wav';
      final r = Process.runSync(ffmpeg, [
        '-nostdin', '-y', '-loglevel', 'error', '-i', src,
        ...gainEncodeArgs(const AudioGain.manual(20), 'wav')!,
        out,
      ]);
      expect(r.exitCode, 0, reason: '${r.stderr}');
      expect(levels(out).max, lessThan(0.01));
    }, skip: have ? false : 'ffmpeg 없음');
  });
}
