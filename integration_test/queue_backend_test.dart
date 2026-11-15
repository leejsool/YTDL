// 재생목록 읽기와 다운로드 대기열을 진짜 DesktopBackend(yt-dlp)로 검증한다(앱 창은 안 띄움, 네트워크 필요).
//
//   flutter test integration_test/queue_backend_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ytdl/backend/desktop_backend.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/state/download_queue.dart';

// 공개 재생목록(유명한 팝송 모음).
const _playlist = 'https://www.youtube.com/playlist?list=PLMC9KNkIncKvYin_USF1qoJQnIyMAfRxl';

void main() {
  late DesktopBackend backend;
  late Directory out;

  setUpAll(() async {
    out = Directory.systemTemp.createTempSync('ytdl_queue_it_');
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

  test('재생목록의 영상 목록을 읽는다', () async {
    final sw = Stopwatch()..start();
    final p = await backend.fetchPlaylist(_playlist, limit: 20);
    // ignore: avoid_print
    print('재생목록 ${sw.elapsedMilliseconds}ms: "${p.title}" ${p.entries.length}개 (전체 ${p.totalCount})');
    expect(p.entries.length, inInclusiveRange(1, 20));
    expect(p.entries.first.url, startsWith('https://www.youtube.com/watch?v='));
    expect(p.entries.first.durationSeconds, greaterThan(0));
    expect(p.entries.first.title, isNotEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('재생목록 앞 3곡을 대기열로 구간 받기(2곡씩 동시에)', () async {
    final p = await backend.fetchPlaylist(_playlist, limit: 3);
    final doneTitles = <String>[];
    final queue = DownloadQueue(
      backend,
      maxParallel: 2,
      onDone: (i) => doneTitles.add(i.title),
    );
    final sw = Stopwatch()..start();
    queue.addPlaylistEntries(
      p.entries.take(3),
      const DownloadOptions(
        kind: MediaKind.audio,
        audioFormat: 'm4a',
        trimStart: 5,
        trimEnd: 12,
      ),
    );

    // 모두 끝날 때까지 기다린다.
    while (queue.activeCount > 0 && sw.elapsed < const Duration(minutes: 3)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    // ignore: avoid_print
    print('대기열 3곡: ${sw.elapsedMilliseconds}ms');

    for (final i in queue.items) {
      expect(i.status, QueueStatus.done, reason: '${i.title}: ${i.error}');
      expect(File(i.result!.filePath!).existsSync(), isTrue);
      expect(File(i.result!.filePath!).lengthSync(), greaterThan(10000));
      expect(i.saved, isNotNull);
    }
    expect(doneTitles, hasLength(3));
    queue.dispose();
  }, timeout: const Timeout(Duration(minutes: 5)));

  test('받는 중인 항목을 취소하면 멈추고 다음 항목이 이어진다', () async {
    final p = await backend.fetchPlaylist(_playlist, limit: 2);
    final queue = DownloadQueue(backend);
    queue.addPlaylistEntries(
      p.entries.take(2),
      const DownloadOptions(kind: MediaKind.audio, audioFormat: 'm4a'),
    );
    final first = queue.items.first;
    final second = queue.items.last;
    // 첫 항목이 실제로 시작할 때까지 기다렸다가 취소한다.
    final sw = Stopwatch()..start();
    while (first.status != QueueStatus.running && sw.elapsed < const Duration(seconds: 30)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    queue.cancel(first);
    while (first.status == QueueStatus.running && sw.elapsed < const Duration(seconds: 60)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(first.status, QueueStatus.cancelled);
    // 다음 항목이 이어서 시작됐는지만 본다(통째로 받으면 오래 걸리니 곧바로 취소한다).
    while (second.status == QueueStatus.waiting && sw.elapsed < const Duration(seconds: 60)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(second.status, QueueStatus.running);
    queue.cancel(second);
    while (queue.activeCount > 0 && sw.elapsed < const Duration(seconds: 90)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    expect(second.status, QueueStatus.cancelled);
    queue.dispose();
  }, timeout: const Timeout(Duration(minutes: 3)));
}
