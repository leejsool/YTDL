import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../models.dart';
import '../state/app_state.dart';
import '../util/names.dart';
import '../widgets/audio_editor.dart';

/// 편집 탭: 컴퓨터/폰에 있는 아무 음원이나, 방금 받은 음원을 열어 듣고 구간을 잘라 새 파일로 저장한다.
class EditPage extends StatefulWidget {
  const EditPage({
    super.key,
    required this.backend,
    required this.controller,
    required this.recent,
    this.active = true,
  });

  final Backend backend;
  final EditController controller;
  final RecentStore recent;
  final bool active;

  @override
  State<EditPage> createState() => _EditPageState();
}

class _EditPageState extends State<EditPage> {
  /// Windows 파일 선택창에 보여 줄 확장자. (-c copy 로 잘라도 문제없는 음원 형식)
  static const supportedExtensions = [
    'mp3',
    'm4a',
    'aac',
    'flac',
    'wav',
    'ogg',
    'oga',
    'opus',
    'wma',
  ];

  String? _note;
  String? _noteForPath;
  String? _error;
  bool _picking = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.recent.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.recent.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() {
      _picking = true;
      _error = null;
    });
    try {
      final files = await FilePicker.pickFiles(
        dialogTitle: '편집할 음원 선택',
        type: Platform.isAndroid ? FileType.audio : FileType.custom,
        allowedExtensions: Platform.isAndroid ? null : supportedExtensions,
      );
      if (!mounted || files.isEmpty) return;
      final f = files.first;
      final path = f.path;
      if (path == null) {
        setState(() => _error = '이 파일의 경로를 읽을 수 없습니다.');
        return;
      }
      openFile(path, displayName: f.name);
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              '파일을 열지 못했습니다: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// 경로로 바로 연다(파일 선택창, 최근 목록, 테스트가 모두 이 길을 쓴다).
  void openFile(String path, {String? displayName}) {
    if (!File(path).existsSync()) {
      setState(() => _error = '파일을 찾을 수 없습니다: $path');
      return;
    }
    widget.controller.openLocal(
      path,
      displayName: displayName,
      recent: widget.recent,
    );
  }

  void _onSaved(SavedAudio s) {
    widget.recent.add(s);
    _note = '새 파일로 저장했어요: ${s.location}';
    _noteForPath = s.path;
    widget.controller.replace(s);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cur = widget.controller.current;
    final recent = widget.recent.items;

    return LayoutBuilder(
      builder: (context, box) {
        final wide = box.maxWidth >= 590;
        final gutter = wide ? 30.0 : 16.0;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1080),
            child: ListView(
              padding: EdgeInsets.fromLTRB(gutter, wide ? 26 : 16, gutter, 20),
              children: [
                _buildHeading(theme, wide, cur != null),
                const SizedBox(height: 18),
                if (cur == null) _buildOpenCard(theme),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ),
                if (cur != null)
                  AudioEditor(
                    // 파일이 바뀌면 새 파일로 편집기를 다시 만든다.
                    key: ValueKey(cur.path),
                    backend: widget.backend,
                    audio: cur,
                    active: widget.active,
                    note: _noteForPath == cur.path ? _note : null,
                    onSaved: _onSaved,
                  ),
                if (recent.isNotEmpty) ...[
                  const SizedBox(height: 24),
                  Text('최근 파일', style: theme.textTheme.titleSmall),
                  const SizedBox(height: 4),
                  for (final a in recent)
                    _recentTile(theme, a, a.path == cur?.path),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _openButton() => FilledButton.tonalIcon(
    onPressed: _picking ? null : _pick,
    icon: const Icon(Icons.folder_open, size: 18),
    label: Text(_picking ? '여는 중…' : '음원 파일 선택'),
  );

  Widget _buildHeading(ThemeData theme, bool wide, bool hasFile) {
    final heading = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '음원 편집',
          style:
              (wide
                      ? theme.textTheme.headlineLarge
                      : theme.textTheme.headlineSmall)
                  ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -1),
        ),
        const SizedBox(height: 4),
        Text(
          '구간을 자르거나 음량을 조절해 새 파일로 저장하세요.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    if (!hasFile) return heading;
    if (wide) {
      return Row(
        children: [
          Expanded(child: heading),
          const SizedBox(width: 10),
          _openButton(),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [heading, const SizedBox(height: 10), _openButton()],
    );
  }

  Widget _buildOpenCard(ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.library_music),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '편집할 음원을 열어 주세요',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              Platform.isAndroid
                  ? '새 파일은 Music/YTDL에 저장됩니다.'
                  : '새 파일은 원본 파일과 같은 폴더에 저장됩니다.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 4),
            Text(
              '열 수 있는 형식: ${supportedExtensions.map((e) => e.toUpperCase()).join(', ')}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            _openButton(),
          ],
        ),
      ),
    );
  }

  Widget _recentTile(ThemeData theme, SavedAudio a, bool selected) {
    return Card(
      color: selected ? theme.colorScheme.secondaryContainer : null,
      margin: const EdgeInsets.only(top: 6),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.music_note),
        title: Text(
          baseNameOf(a.path),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          a.location,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: IconButton(
          tooltip: '목록에서 빼기 (파일은 지워지지 않아요)',
          icon: const Icon(Icons.close),
          onPressed: () => widget.recent.remove(a),
        ),
        onTap: () {
          if (File(a.path).existsSync()) {
            widget.controller.open(a);
          } else {
            widget.recent.remove(a);
            setState(() => _error = '파일이 없어져서 목록에서 뺐어요: ${baseNameOf(a.path)}');
          }
        },
      ),
    );
  }
}
