import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend/backend.dart';
import '../models.dart';
import '../util/names.dart';

enum QueueStatus { waiting, running, done, failed, cancelled }

/// 대기열에 담긴 다운로드 하나.
class QueueItem {
  QueueItem({
    required this.id,
    required this.url,
    required this.title,
    required this.options,
    this.uploader = '',
    this.thumbnail,
    this.durationSeconds,
    this.info,
  });

  final int id;
  final String url;
  final String title;
  final String uploader;
  final String? thumbnail;
  final int? durationSeconds;

  /// 담을 때의 옵션(영상 형식·화질·구간·음량). [DownloadOptions.infoJson] 은 쓰지 않고 [info] 로 정한다.
  final DownloadOptions options;

  /// 영상 하나를 조회해서 담았다면 그 정보. 받을 때 아직 신선하면 분석을 건너뛴다.
  final MediaInfo? info;

  QueueStatus status = QueueStatus.waiting;
  DownloadProgress? progress;
  DownloadResult? result;
  String? error;
  CancelToken? _token;

  /// 받기가 끝난 파일(편집 탭으로 넘길 때 쓴다). 영상이면 영상 편집 쪽 것이다.
  SavedAudio? saved;

  bool get isVideo => options.kind == MediaKind.video;
  bool get isActive =>
      status == QueueStatus.waiting || status == QueueStatus.running;
  bool get isFinished => !isActive;
}

/// 다운로드 대기열. 담은 순서대로 [maxParallel] 개씩 받는다.
/// 한 번 담으면 다운로드 탭에서 다른 영상을 조회하거나 탭을 옮겨도 계속 받는다.
class DownloadQueue extends ChangeNotifier {
  DownloadQueue(this.backend, {this.maxParallel = 1, this.onDone});

  final Backend backend;
  final int maxParallel;

  /// 한 항목이 성공적으로 끝났을 때(최근 파일 목록에 올리는 데 쓴다).
  final void Function(QueueItem item)? onDone;

  final List<QueueItem> _items = [];
  int _seq = 0;
  int _running = 0;
  bool _disposed = false;

  List<QueueItem> get items => List.unmodifiable(_items);

  /// 기다리거나 받는 중인 항목 수.
  int get activeCount => _items.where((i) => i.isActive).length;
  bool get hasFinished => _items.any((i) => i.isFinished);

  QueueItem add({
    required String url,
    required String title,
    required DownloadOptions options,
    String uploader = '',
    String? thumbnail,
    int? durationSeconds,
    MediaInfo? info,
  }) {
    final item = QueueItem(
      id: ++_seq,
      url: url,
      title: title,
      options: options,
      uploader: uploader,
      thumbnail: thumbnail,
      durationSeconds: durationSeconds,
      info: info,
    );
    _items.add(item);
    _changed();
    _pump();
    return item;
  }

  /// 재생목록에서 고른 영상들을 같은 옵션으로 한꺼번에 담는다.
  List<QueueItem> addPlaylistEntries(
    Iterable<PlaylistEntry> entries,
    DownloadOptions options,
  ) {
    final added = [
      for (final e in entries)
        _enqueue(
          QueueItem(
            id: ++_seq,
            url: e.url,
            title: e.title,
            options: options,
            uploader: e.uploader,
            thumbnail: e.thumbnail,
            durationSeconds: e.durationSeconds,
          ),
        ),
    ];
    _changed();
    _pump();
    return added;
  }

  QueueItem _enqueue(QueueItem item) {
    _items.add(item);
    return item;
  }

  /// 기다리는 항목은 바로 취소하고, 받는 중이면 멈춘다.
  void cancel(QueueItem item) {
    if (item.status == QueueStatus.waiting) {
      item.status = QueueStatus.cancelled;
      _changed();
    } else if (item.status == QueueStatus.running) {
      item._token?.cancel();
    }
  }

  void cancelAll() {
    for (final i in List.of(_items)) {
      cancel(i);
    }
  }

  /// 실패·취소한 항목을 맨 뒤에서 다시 시작한다.
  void retry(QueueItem item) {
    if (item.status != QueueStatus.failed &&
        item.status != QueueStatus.cancelled) {
      return;
    }
    item
      ..status = QueueStatus.waiting
      ..error = null
      ..progress = null
      ..result = null;
    _items
      ..remove(item)
      ..add(item);
    _changed();
    _pump();
  }

  void remove(QueueItem item) {
    if (item.isActive) return;
    _items.remove(item);
    _changed();
  }

  void clearFinished() {
    _items.removeWhere((i) => i.isFinished);
    _changed();
  }

  void _pump() {
    while (_running < maxParallel) {
      final next = _items
          .where((i) => i.status == QueueStatus.waiting)
          .firstOrNull;
      if (next == null) return;
      _running++;
      unawaited(_run(next));
    }
  }

  Future<void> _run(QueueItem item) async {
    final token = CancelToken();
    item
      ..status = QueueStatus.running
      .._token = token
      ..progress = const DownloadProgress(stage: '시작하는 중…');
    _changed();
    try {
      // 조회해 둔 정보가 아직 신선하면 yt-dlp 가 분석을 다시 하지 않는다.
      final options = item.options.withInfo(item.info);
      var lastPercent = -1.0;
      final r = await backend.download(item.url, options, (p) {
        if (token.cancelled) return;
        // 1% 단위로만 화면을 갱신한다(yt-dlp 는 초당 여러 줄을 내보낸다).
        final percent = p.percent ?? -1;
        final same = item.progress?.stage == p.stage && (percent - lastPercent).abs() < 0.01;
        item.progress = p;
        if (!same) {
          lastPercent = percent;
          _changed();
        }
      }, token);
      if (token.cancelled) throw CancelledException();
      item
        ..result = r
        ..status = QueueStatus.done
        ..progress = null
        ..saved = _savedFor(item, r);
      _changed();
      onDone?.call(item);
    } on CancelledException {
      item
        ..status = QueueStatus.cancelled
        ..progress = null
        ..error = null;
    } catch (e) {
      item
        ..status = QueueStatus.failed
        ..progress = null
        ..error = e.toString().replaceFirst('Exception: ', '');
    } finally {
      item._token = null;
      _running--;
      _changed();
      _pump();
    }
  }

  SavedAudio? _savedFor(QueueItem item, DownloadResult r) {
    final path = r.filePath;
    if (path == null) return null;
    final o = item.options;
    return SavedAudio(
      title: stripCut(baseNameOf(path)),
      path: path,
      location: r.location,
      srcStart: (o.trimStart ?? 0).toDouble(),
      srcEnd: (o.trimEnd ?? item.durationSeconds ?? 0).toDouble(),
      sourceLabel: '원본 영상',
    );
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final i in _items) {
      i._token?.cancel();
    }
    super.dispose();
  }
}
