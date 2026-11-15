import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../state/download_queue.dart';
import '../util/names.dart';
import '../util/time_format.dart';
import '../widgets/pill_button.dart';

/// 대기열 탭: 담아 둔 다운로드의 진행 상황을 보고, 취소·다시 시도하고, 끝난 파일을 열거나 편집한다.
class QueuePage extends StatelessWidget {
  const QueuePage({
    super.key,
    required this.queue,
    required this.backend,
    required this.audioController,
    required this.videoController,
  });

  final DownloadQueue queue;
  final Backend backend;

  /// "편집하기" 가 음원/영상 편집 탭에 파일을 넘기는 데 쓴다.
  final EditController audioController;
  final EditController videoController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: queue,
      builder: (context, _) {
        final theme = Theme.of(context);
        final items = queue.items;
        return LayoutBuilder(
          builder: (context, box) {
            final wide = box.maxWidth >= 590;
            final gutter = wide ? 30.0 : 16.0;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1080),
                child: ListView(
                  padding: EdgeInsets.fromLTRB(
                    gutter,
                    wide ? 26 : 16,
                    gutter,
                    20,
                  ),
                  children: [
                    _heading(theme, wide, items),
                    const SizedBox(height: 18),
                    if (items.isEmpty) _empty(theme),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _tile(context, theme, item, wide),
                      ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _heading(ThemeData theme, bool wide, List<QueueItem> items) {
    final active = queue.activeCount;
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '대기열',
          style:
              (wide
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
        ),
        const SizedBox(height: 4),
        Text(
          items.isEmpty
              ? '담아 둔 영상이나 재생목록을 순서대로 받아요.'
              : active > 0
              ? '$active개 남았어요. 다른 탭으로 옮겨도 계속 받아요.'
              : '모두 끝났어요.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final actions = [
      if (active > 0)
        PillButton(
          onPressed: queue.cancelAll,
          icon: const Icon(Icons.cancel_outlined, size: 18),
          label: const Text('모두 취소'),
        ),
      if (queue.hasFinished)
        PillButton(
          onPressed: queue.clearFinished,
          icon: const Icon(Icons.clear_all, size: 18),
          label: const Text('끝난 항목 지우기'),
        ),
    ];
    if (actions.isEmpty) return heading;
    final row = Wrap(spacing: 8, runSpacing: 8, children: actions);
    if (wide) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: heading), const SizedBox(width: 10), row],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [heading, const SizedBox(height: 10), row],
    );
  }

  Widget _empty(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(Icons.queue_music, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                '대기열이 비어 있어요.\n다운로드 탭에서 영상을 조회한 뒤 "대기열에 담기"를 누르거나, '
                '재생목록 주소를 넣어 보세요.',
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// "MP3" / "MP4 720p" + 구간 + 음량.
  String _optionsLabel(DownloadOptions o) {
    final parts = <String>[
      if (o.kind == MediaKind.audio)
        o.audioFormat.toUpperCase()
      else
        'MP4 ${o.maxHeight == null ? '최고' : '${o.maxHeight}p'}',
      if (o.hasTrim) '${formatSeconds(o.trimStart!)}–${formatSeconds(o.trimEnd!)}',
      if (o.kind == MediaKind.audio && o.gain.isActive) o.gain.nameTag.trim(),
    ];
    return parts.join(' · ');
  }

  Widget _tile(
    BuildContext context,
    ThemeData theme,
    QueueItem item,
    bool wide,
  ) {
    final colors = theme.colorScheme;
    final p = item.progress;
    final (statusText, statusColor) = switch (item.status) {
      QueueStatus.waiting => ('대기 중', colors.onSurfaceVariant),
      QueueStatus.running => (
        p == null
            ? '받는 중'
            : p.percent != null
            ? '${p.stage} ${(p.percent! * 100).toStringAsFixed(0)}%'
            : p.stage,
        colors.primary,
      ),
      QueueStatus.done => ('저장 완료', colors.primary),
      QueueStatus.failed => ('실패', colors.error),
      QueueStatus.cancelled => ('취소함', colors.onSurfaceVariant),
    };

    final thumb = SizedBox(
      width: wide ? 120 : 84,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: item.thumbnail == null
              ? ColoredBox(
                  color: colors.surfaceContainerHighest,
                  child: Icon(
                    item.isVideo ? Icons.movie_outlined : Icons.music_note,
                    color: colors.primary,
                  ),
                )
              : Image.network(
                  item.thumbnail!,
                  fit: BoxFit.cover,
                  cacheWidth: 240,
                  errorBuilder: (_, _, _) => ColoredBox(
                    color: colors.surfaceContainerHighest,
                    child: Icon(Icons.movie_outlined, color: colors.primary),
                  ),
                ),
        ),
      ),
    );

    final actions = <Widget>[
      if (item.isActive)
        IconButton(
          tooltip: '취소',
          onPressed: () => queue.cancel(item),
          icon: const Icon(Icons.close),
        ),
      if (item.status == QueueStatus.done) ...[
        if (backend.canReveal && item.result?.filePath != null)
          IconButton(
            tooltip: '폴더 열기',
            onPressed: () => backend.reveal(item.result!),
            icon: const Icon(Icons.folder_open),
          ),
        if (item.saved != null)
          IconButton(
            tooltip: item.isVideo ? '영상 편집하기' : '음원 편집하기',
            onPressed: () => (item.isVideo ? videoController : audioController)
                .open(item.saved!),
            icon: Icon(item.isVideo ? Icons.movie_creation_outlined : Icons.content_cut),
          ),
      ],
      if (item.status == QueueStatus.failed ||
          item.status == QueueStatus.cancelled)
        IconButton(
          tooltip: '다시 시도',
          onPressed: () => queue.retry(item),
          icon: const Icon(Icons.refresh),
        ),
      if (item.isFinished)
        IconButton(
          tooltip: '목록에서 지우기 (받은 파일은 지워지지 않아요)',
          onPressed: () => queue.remove(item),
          icon: const Icon(Icons.delete_outline),
        ),
    ];

    return Card(
      color: item.status == QueueStatus.running
          ? colors.secondaryContainer
          : null,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            thumb,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      _optionsLabel(item.options),
                      if (item.uploader.isNotEmpty) item.uploader,
                    ].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    statusText,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (item.status == QueueStatus.running)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: LinearProgressIndicator(value: p?.percent),
                    ),
                  if (item.status == QueueStatus.failed && item.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        item.error!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                    ),
                  if (item.status == QueueStatus.done &&
                      item.result != null)
                    Tooltip(
                      message: item.result!.location,
                      child: Text(
                        baseNameOf(item.result!.filePath ?? item.result!.location),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall,
                      ),
                    ),
                  // 좁은 화면에서는 버튼을 글 아래에 둔다(옆에 두면 글이 너무 좁아진다).
                  if (!wide && actions.isNotEmpty)
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: actions,
                      ),
                    ),
                ],
              ),
            ),
            if (wide && actions.isNotEmpty)
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: actions,
              ),
          ],
        ),
      ),
    );
  }
}
