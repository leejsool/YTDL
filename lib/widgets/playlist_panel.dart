import 'package:flutter/material.dart';

import '../models.dart';
import '../state/settings.dart';
import '../util/time_format.dart';
import 'edit_media_icon.dart';
import 'pill_button.dart';
import 'sliding_choice.dart';

/// 재생목록에서 받을 영상을 고르고, 형식·화질을 정해 대기열에 담는 카드.
class PlaylistPanel extends StatefulWidget {
  const PlaylistPanel({
    super.key,
    required this.playlist,
    required this.settings,
    required this.onAdd,
  });

  final PlaylistInfo playlist;

  /// 형식·화질의 처음 값(옵션 탭 기본값).
  final AppSettings settings;

  /// 고른 영상들을 같은 옵션으로 대기열에 담는다.
  final void Function(List<PlaylistEntry> entries, DownloadOptions options) onAdd;

  @override
  State<PlaylistPanel> createState() => _PlaylistPanelState();
}

class _PlaylistPanelState extends State<PlaylistPanel> {
  late final Set<String> _selected = {
    for (final e in widget.playlist.entries) e.id,
  };
  MediaKind _kind = MediaKind.audio;
  late String _audioFormat = widget.settings.audioFormat;
  late int? _maxHeight = widget.settings.maxHeight;

  List<PlaylistEntry> get _chosen => [
    for (final e in widget.playlist.entries)
      if (_selected.contains(e.id)) e,
  ];

  int get _totalSeconds =>
      _chosen.fold(0, (sum, e) => sum + (e.durationSeconds ?? 0));

  void _add() {
    final chosen = _chosen;
    if (chosen.isEmpty) return;
    widget.onAdd(
      chosen,
      DownloadOptions(
        kind: _kind,
        audioFormat: _audioFormat,
        maxHeight: _maxHeight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final p = widget.playlist;
    final entries = p.entries;
    final allSelected = _selected.length == entries.length;
    final listHeight = (entries.length * 64.0).clamp(120.0, 380.0);

    final notes = <String>[
      if (p.truncated) '앞의 ${entries.length}개만 불러왔어요(전체 ${p.totalCount}개)',
      if (p.skipped > 0) '비공개·삭제된 영상 ${p.skipped}개는 뺐어요',
    ];

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 13, 13, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.queue_music, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    p.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              [
                if (p.uploader.isNotEmpty) p.uploader,
                '영상 ${entries.length}개',
              ].join(' · '),
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
            for (final n in notes)
              Text(
                n,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            const SizedBox(height: 12),
            SegmentedButton<MediaKind>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                backgroundColor: colors.surfaceContainerHighest,
                selectedBackgroundColor: colors.secondaryContainer,
                selectedForegroundColor: colors.primary,
                side: BorderSide(color: colors.outlineVariant),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              segments: const [
                ButtonSegment(
                  value: MediaKind.audio,
                  icon: Icon(Icons.headphones, size: 17),
                  label: Text('음원'),
                ),
                ButtonSegment(
                  value: MediaKind.video,
                  icon: EditMediaIcon.video(size: 17),
                  label: Text('영상'),
                ),
              ],
              selected: {_kind},
              onSelectionChanged: (s) => setState(() => _kind = s.first),
            ),
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxWidth: _kind == MediaKind.audio ? 282 : 392,
                ),
                child: _kind == MediaKind.audio
                    ? SlidingChoice<String>(
                        values: AppSettings.audioFormats,
                        value: _audioFormat,
                        labelBuilder: (format) => format.toUpperCase(),
                        onChanged: (format) =>
                            setState(() => _audioFormat = format),
                      )
                    : SlidingChoice<int?>(
                        values: AppSettings.videoHeights,
                        value: _maxHeight,
                        labelBuilder: (height) =>
                            height == null ? '최고' : '${height}p',
                        onChanged: (height) =>
                            setState(() => _maxHeight = height),
                      ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                TextButton(
                  onPressed: () => setState(() {
                    if (allSelected) {
                      _selected.clear();
                    } else {
                      _selected.addAll(entries.map((e) => e.id));
                    }
                  }),
                  child: Text(allSelected ? '모두 해제' : '모두 선택'),
                ),
                Expanded(
                  child: Text(
                    '${_selected.length}개 선택'
                    '${_totalSeconds > 0 ? ' · ${formatSeconds(_totalSeconds)}' : ''}',
                    textAlign: TextAlign.end,
                    style: theme.textTheme.labelMedium,
                  ),
                ),
              ],
            ),
            SizedBox(
              height: listHeight,
              child: ListView.builder(
                itemCount: entries.length,
                itemExtent: 64,
                itemBuilder: (context, i) => _tile(theme, entries[i]),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: PillButton(
                onPressed: _selected.isEmpty ? null : _add,
                icon: const Icon(Icons.playlist_add, size: 19),
                label: Text('대기열에 담기 (${_selected.length})'),
              ),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _tile(ThemeData theme, PlaylistEntry e) {
    final colors = theme.colorScheme;
    final checked = _selected.contains(e.id);
    return InkWell(
      onTap: () => setState(() {
        if (checked) {
          _selected.remove(e.id);
        } else {
          _selected.add(e.id);
        }
      }),
      child: Row(
        children: [
          Checkbox(
            value: checked,
            visualDensity: VisualDensity.compact,
            onChanged: (v) => setState(() {
              if (v == true) {
                _selected.add(e.id);
              } else {
                _selected.remove(e.id);
              }
            }),
          ),
          SizedBox(
            width: 80,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: e.thumbnail == null
                    ? ColoredBox(color: colors.surfaceContainerHighest)
                    : Image.network(
                        e.thumbnail!,
                        fit: BoxFit.cover,
                        cacheWidth: 160,
                        errorBuilder: (_, _, _) =>
                            ColoredBox(color: colors.surfaceContainerHighest),
                      ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  e.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                Text(
                  [
                    if (e.uploader.isNotEmpty) e.uploader,
                    if (e.durationSeconds != null)
                      formatSeconds(e.durationSeconds!),
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
