import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../util/preview_media.dart';
import '../util/time_format.dart';
import 'loading_stripes.dart';
import 'pill_button.dart';

/// 구간 자르기 미리보기: 시작/끝 지점의 장면 + 그 구간을 소리로 들어 보기.
/// 영상 전체를 받지 않고 유튜브가 주는 장면 모음 그림과 소리 스트림으로 보여 준다.
/// 둘 중 하나라도 없으면 있는 것만 보여 주고, 둘 다 없으면 아무것도 그리지 않는다.
class RangePreview extends StatefulWidget {
  const RangePreview({
    super.key,
    required this.start,
    required this.end,
    this.storyboard,
    this.render,
    this.enabled = true,
  });

  /// 자를 구간(초).
  final int start;
  final int end;
  final Storyboard? storyboard;

  /// [start]~[end] 초 구간의 (음량이 적용된) 소리 파일 경로를 만들어 준다. null 이면 듣기 버튼을 숨긴다.
  final Future<String> Function(int start, int end)? render;
  final bool enabled;

  @override
  State<RangePreview> createState() => _RangePreviewState();
}

class _RangePreviewState extends State<RangePreview> {
  /// 시작/끝 부분 듣기 길이(초)
  static const _peekSec = 3;

  /// 한 번에 들어 볼 수 있는 최대 길이(초). 더 길면 처음 부분만 들려 준다.
  static const _maxListenSec = 120;

  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _loading = false;
  bool _playing = false;
  bool _everPlayed = false; // 한 번이라도 들었으면 재생 위치 장면을 보여 준다
  int _offsetMs = 0;
  int _posMs = 0;
  String? _error;
  String? _notice;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final p = _player = AudioPlayer();
    _subs.add(
      p.onPositionChanged.listen((d) {
        if (mounted) setState(() => _posMs = _offsetMs + d.inMilliseconds);
      }),
    );
    _subs.add(
      p.onPlayerStateChanged.listen((s) {
        if (!mounted) return;
        setState(() => _playing = s == PlayerState.playing);
      }),
    );
    _subs.add(
      p.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      }),
    );
    return p;
  }

  /// [fromSec]~[toSec] 를 (지금 고른 음량으로) 들려 준다. 끝까지 재생하면 저절로 멈춘다.
  Future<void> _play(int fromSec, int toSec) async {
    final render = widget.render;
    if (render == null || _loading) return;
    final capped = toSec - fromSec > _maxListenSec;
    final to = capped ? fromSec + _maxListenSec : toSec;
    setState(() {
      _loading = true;
      _error = null;
      _notice = capped ? '구간이 길어서 처음 ${_maxListenSec ~/ 60}분만 들려 드려요.' : null;
    });
    try {
      final path = await render(fromSec, to);
      if (!mounted) return;
      final p = _ensurePlayer();
      await p.setReleaseMode(ReleaseMode.stop);
      await p.stop();
      _offsetMs = fromSec * 1000;
      _posMs = _offsetMs;
      await p.play(DeviceFileSource(path));
      if (mounted) setState(() => _everPlayed = true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              '소리를 만들지 못했어요: ${e.toString().replaceFirst('Exception: ', '')}';
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _stop() async {
    await _player?.stop();
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.storyboard;
    final hasAudio = widget.render != null;
    if (board == null && !hasAudio) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final s = widget.start;
    final e = widget.end;
    // 끝 장면은 마지막 1초 안쪽을 보여 준다(끝 시각 바로 뒤는 이미 잘려 나가는 부분).
    final endFrameAt = (e - 1).clamp(s, e).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.preview_outlined, size: 17, color: colors.primary),
            const SizedBox(width: 7),
            Text('구간 미리보기', style: theme.textTheme.titleSmall),
          ],
        ),
        if (board != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _FrameCard(
                  label: '시작 ${formatSeconds(s)}',
                  board: board,
                  seconds: s.toDouble(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _FrameCard(
                  label: '끝 ${formatSeconds(e)}',
                  board: board,
                  seconds: endFrameAt,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '장면은 약 ${board.intervalSeconds.round()}초 간격 사진이라 대략적인 위치예요.'
            '${hasAudio ? ' 정확한 지점은 소리로 확인해 보세요.' : ''}',
            style: small,
          ),
        ],
        // 소리를 들을 때는 지금 재생 위치의 장면(약 10초 간격 사진)을 함께 보여 준다.
        if (board != null && hasAudio && _everPlayed) ...[
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.center,
            child: FractionallySizedBox(
              widthFactor: .6,
              child: _FrameCard(
                label: '${_playing ? '재생 중' : '멈춤'} ${formatMs(_posMs)}',
                board: board,
                seconds: (_posMs / 1000).clamp(s.toDouble(), e.toDouble()),
              ),
            ),
          ),
        ],
        if (hasAudio) ...[
          const SizedBox(height: 10),
          // 글자 없이 아이콘만, 시작 부분 · 선택 구간 · 끝 부분 순서로 가운데에 놓는다.
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PillButton(
                tooltip: '시작 부분 듣기',
                onPressed: widget.enabled && !_loading
                    ? () => _play(s, (s + _peekSec).clamp(s, e))
                    : null,
                icon: const Icon(Icons.skip_previous, size: 24),
              ),
              const SizedBox(width: 10),
              PillButton(
                tooltip: _playing ? '정지' : '선택 구간 듣기',
                selected: _playing,
                onPressed: _playing
                    ? _stop
                    : (widget.enabled && !_loading ? () => _play(s, e) : null),
                icon: _loading
                    ? const SizedBox.square(
                        dimension: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : Icon(_playing ? Icons.pause : Icons.play_arrow, size: 28),
              ),
              const SizedBox(width: 10),
              PillButton(
                tooltip: '끝 부분 듣기',
                onPressed: widget.enabled && !_loading
                    ? () => _play((e - _peekSec).clamp(s, e), e)
                    : null,
                icon: const Icon(Icons.skip_next, size: 24),
              ),
            ],
          ),
        ],
        if (_notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_notice!, style: small),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(_error!, style: TextStyle(color: colors.error)),
          ),
      ],
    );
  }
}

/// 장면 한 장 + 시각 표시.
class _FrameCard extends StatelessWidget {
  const _FrameCard({
    required this.label,
    required this.board,
    required this.seconds,
  });

  final String label;
  final Storyboard board;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(7),
          child: AspectRatio(
            aspectRatio: board.aspectRatio,
            child: StoryboardFrameView(board: board, seconds: seconds),
          ),
        ),
        const SizedBox(height: 3),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(color: colors.primary),
        ),
      ],
    );
  }
}

/// 스토리보드 그림에서 [seconds] 시각의 장면 한 칸만 잘라서 보여 준다.
class StoryboardFrameView extends StatefulWidget {
  const StoryboardFrameView({
    super.key,
    required this.board,
    required this.seconds,
  });

  final Storyboard board;
  final double seconds;

  @override
  State<StoryboardFrameView> createState() => _StoryboardFrameViewState();
}

class _StoryboardFrameViewState extends State<StoryboardFrameView> {
  // 그림이 오기 전에는 사선 무늬(로딩 중 표시), 오거나 실패하면 무늬 애니메이션을 멈춘다.
  bool _settled = false;

  void _settle() {
    if (_settled) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _settled = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final f = widget.board.frameAt(widget.seconds);
    // 격자 안의 칸 위치를 Align 의 -1~1 좌표로 바꾼다(칸이 하나면 가운데).
    double axis(int index, int count) =>
        count <= 1 ? 0 : -1 + 2 * index / (count - 1);

    return Stack(
      fit: StackFit.expand,
      children: [
        if (_settled)
          ColoredBox(color: colors.surfaceContainerHighest)
        else
          const LoadingStripes(),
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: ClipRect(
            child: Align(
              alignment: Alignment(
                axis(f.column, f.columns),
                axis(f.row, f.rows),
              ),
              widthFactor: 1 / f.columns,
              heightFactor: 1 / f.rows,
              child: Image.network(
                f.url,
                // 같은 그림 한 장에서 여러 칸을 쓰므로 바뀔 때 깜빡이지 않게 이전 그림을 유지한다.
                gaplessPlayback: true,
                frameBuilder: (context, child, frame, sync) {
                  if (frame != null || sync) _settle();
                  return child;
                },
                errorBuilder: (_, _, _) {
                  _settle();
                  return const SizedBox.shrink();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 영상 정보를 아직 못 받았을 때 보여 주는 구간 미리보기 뼈대(흐리게 · 누를 수 없게 쓴다).
class RangePreviewSkeleton extends StatelessWidget {
  const RangePreviewSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    Widget frame(String label) => Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: const AspectRatio(
              aspectRatio: 16 / 9,
              child: LoadingStripes(),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: colors.primary),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        Row(
          children: [
            Icon(Icons.preview_outlined, size: 17, color: colors.primary),
            const SizedBox(width: 7),
            Text('구간 미리보기', style: theme.textTheme.titleSmall),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [frame('시작 ??'), const SizedBox(width: 10), frame('끝 ??')],
        ),
        const SizedBox(height: 4),
        Text(
          '장면은 약 ??초 간격 사진이라 대략적인 위치예요.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            PillButton(
              onPressed: null,
              icon: Icon(Icons.skip_previous, size: 24),
            ),
            SizedBox(width: 10),
            PillButton(onPressed: null, icon: Icon(Icons.play_arrow, size: 28)),
            SizedBox(width: 10),
            PillButton(onPressed: null, icon: Icon(Icons.skip_next, size: 24)),
          ],
        ),
      ],
    );
  }
}
