import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ytdl/backend/backend.dart';
import 'package:ytdl/models.dart';
import 'package:ytdl/state/download_queue.dart';

/// 받기를 우리가 직접 끝내거나 실패시킬 수 있는 가짜 엔진.
class _Backend extends Backend {
  final started = <String>[];
  final _gates = <String, Completer<DownloadResult>>{};
  final infoJsonSeen = <String, String?>{};
  int running = 0;
  int maxRunning = 0;

  Completer<DownloadResult> gate(String url) =>
      _gates.putIfAbsent(url, Completer.new);

  void finish(String url, {String? path}) => gate(url).complete(
    DownloadResult(location: 'C:/out', filePath: path ?? 'C:/out/$url.mp3'),
  );

  void fail(String url, Object error) => gate(url).completeError(error);

  @override
  String get saveLocationLabel => 'x';
  @override
  Future<void> prepare(SetupCallback onStatus) async {}
  @override
  Future<MediaInfo> fetchInfo(String url) async => throw UnimplementedError();
  @override
  Future<double> measureGain(
    String source,
    CancelToken token, {
    bool remote = false,
    double? startSec,
    double? endSec,
  }) async => 0;
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

  @override
  Future<DownloadResult> download(
    String url,
    DownloadOptions options,
    void Function(DownloadProgress) onProgress,
    CancelToken token,
  ) async {
    started.add(url);
    infoJsonSeen[url] = options.infoJson;
    running++;
    if (running > maxRunning) maxRunning = running;
    onProgress(const DownloadProgress(percent: 0.5, stage: '다운로드 중'));
    final done = Completer<void>();
    token.onCancel = () {
      if (!done.isCompleted) done.complete();
    };
    try {
      final result = await Future.any([
        gate(url).future,
        done.future.then((_) => throw CancelledException()),
      ]);
      return result;
    } finally {
      running--;
    }
  }
}

const _audio = DownloadOptions(kind: MediaKind.audio);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('담은 순서대로 하나씩 받는다', () async {
    final b = _Backend();
    final q = DownloadQueue(b);
    final a = q.add(url: 'a', title: 'A', options: _audio);
    final c = q.add(url: 'c', title: 'C', options: _audio);
    await _settle();

    expect(b.started, ['a']);
    expect(a.status, QueueStatus.running);
    expect(c.status, QueueStatus.waiting);
    expect(q.activeCount, 2);

    b.finish('a');
    await _settle();
    await _settle();
    expect(a.status, QueueStatus.done);
    expect(b.started, ['a', 'c']);
    expect(c.status, QueueStatus.running);

    b.finish('c');
    await _settle();
    await _settle();
    expect(q.activeCount, 0);
    expect(b.maxRunning, 1);
  });

  test('동시에 받는 수는 maxParallel 을 넘지 않는다', () async {
    final b = _Backend();
    final q = DownloadQueue(b, maxParallel: 2);
    for (final u in ['1', '2', '3', '4']) {
      q.add(url: u, title: u, options: _audio);
    }
    await _settle();
    expect(b.started, ['1', '2']);

    b.finish('1');
    await _settle();
    await _settle();
    expect(b.started, ['1', '2', '3']);
    expect(b.maxRunning, 2);
  });

  test('실패해도 다음 항목은 계속 받고, 다시 시도하면 맨 뒤에서 다시 받는다', () async {
    final b = _Backend();
    final q = DownloadQueue(b);
    final bad = q.add(url: 'bad', title: 'bad', options: _audio);
    final ok = q.add(url: 'ok', title: 'ok', options: _audio);
    await _settle();

    b.fail('bad', Exception('403 Forbidden'));
    await _settle();
    await _settle();
    expect(bad.status, QueueStatus.failed);
    expect(bad.error, '403 Forbidden');
    expect(ok.status, QueueStatus.running);

    b.finish('ok');
    await _settle();
    await _settle();

    // 다시 시도: 새로 받기 시작한다.
    b._gates.remove('bad');
    q.retry(bad);
    await _settle();
    expect(bad.status, QueueStatus.running);
    expect(bad.error, isNull);
    expect(q.items.last, bad);
    b.finish('bad');
    await _settle();
    await _settle();
    expect(bad.status, QueueStatus.done);
  });

  test('기다리는 항목은 바로 취소되고, 받는 중인 항목은 받기를 멈춘다', () async {
    final b = _Backend();
    final q = DownloadQueue(b);
    final first = q.add(url: 'a', title: 'A', options: _audio);
    final second = q.add(url: 'c', title: 'C', options: _audio);
    await _settle();

    q.cancel(second);
    expect(second.status, QueueStatus.cancelled);

    q.cancel(first);
    await _settle();
    await _settle();
    expect(first.status, QueueStatus.cancelled);
    expect(b.started, ['a'], reason: '취소한 항목은 시작하지 않는다');
    expect(q.activeCount, 0);
  });

  test('모두 취소 / 끝난 항목 지우기', () async {
    final b = _Backend();
    final q = DownloadQueue(b);
    q.add(url: 'a', title: 'A', options: _audio);
    q.add(url: 'c', title: 'C', options: _audio);
    q.add(url: 'd', title: 'D', options: _audio);
    await _settle();

    q.cancelAll();
    await _settle();
    await _settle();
    expect(q.items.every((i) => i.status == QueueStatus.cancelled), isTrue);
    expect(q.hasFinished, isTrue);

    q.clearFinished();
    expect(q.items, isEmpty);
  });

  test('끝나면 onDone 에 저장된 파일 정보가 온다', () async {
    final b = _Backend();
    final done = <QueueItem>[];
    final q = DownloadQueue(b, onDone: done.add);
    q.add(
      url: 'a',
      title: 'A',
      options: const DownloadOptions(
        kind: MediaKind.audio,
        trimStart: 10,
        trimEnd: 40,
      ),
      durationSeconds: 200,
    );
    await _settle();
    b.finish('a', path: 'C:/out/Song (cut 0m10s-0m40s).mp3');
    await _settle();
    await _settle();

    expect(done, hasLength(1));
    final saved = done.single.saved!;
    expect(saved.title, 'Song');
    expect(saved.srcStart, 10);
    expect(saved.srcEnd, 40);
    expect(done.single.isVideo, isFalse);
  });

  test('조회해 둔 정보가 신선하면 받을 때 넘기고, 오래됐으면 넘기지 않는다', () async {
    final b = _Backend();
    final q = DownloadQueue(b);
    final fresh = MediaInfo(
      id: 'f',
      title: 'fresh',
      uploader: '',
      url: 'fresh',
      durationSeconds: 10,
      rawJson: '{"id":"f"}',
    );
    final stale = MediaInfo(
      id: 's',
      title: 'stale',
      uploader: '',
      url: 'stale',
      durationSeconds: 10,
      rawJson: '{"id":"s"}',
      fetchedAt: DateTime.now().subtract(const Duration(hours: 3)),
    );
    q.add(url: 'fresh', title: 'fresh', options: _audio, info: fresh);
    q.add(url: 'stale', title: 'stale', options: _audio, info: stale);
    await _settle();
    b.finish('fresh');
    await _settle();
    await _settle();

    expect(b.infoJsonSeen['fresh'], '{"id":"f"}');
    expect(b.infoJsonSeen['stale'], isNull);
  });

  test('재생목록 항목은 같은 옵션으로 한꺼번에 담긴다', () async {
    final b = _Backend();
    final q = DownloadQueue(b);
    final added = q.addPlaylistEntries(
      const [
        PlaylistEntry(id: 'x1', title: 'X1', url: 'u1'),
        PlaylistEntry(id: 'x2', title: 'X2', url: 'u2', uploader: '채널'),
      ],
      const DownloadOptions(kind: MediaKind.video, maxHeight: 720),
    );
    await _settle();
    expect(added.map((i) => i.title), ['X1', 'X2']);
    expect(added.every((i) => i.options.maxHeight == 720), isTrue);
    expect(added.first.isVideo, isTrue);
    expect(b.started, ['u1']);
  });
}
