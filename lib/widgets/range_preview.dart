import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../util/preview_media.dart';
import '../util/time_format.dart';

/// 구간 자르기 미리보기: 시작/끝 지점의 장면 + 그 구간을 소리로 들어 보기.
/// 영상 전체를 받지 않고 유튜브가 주는 장면 모음 그림과 소리 스트림으로 보여 준다.
/// 둘 중 하나라도 없으면 있는 것만 보여 주고, 둘 다 없으면 아무것도 그리지 않는다.
class RangePreview extends StatefulWidget {
  const RangePreview({
    super.key,
    required this.start,
    required this.end,
    this.storyboard,
    this.audioUrl,
    this.enabled = true,
  });

  /// 자를 구간(초).
  final int start;
  final int end;
  final Storyboard? storyboard;
  final String? audioUrl;
  final bool enabled;

  @override
  State<RangePreview> createState() => _RangePreviewState();
}

class _RangePreviewState extends State<RangePreview> {
  /// 시작/끝 부분 듣기 길이(초)
  static const _peekSec = 3;

  AudioPlayer? _player;
  final List<StreamSubscription<dynamic>> _subs = [];
  Future<void>? _prepared;
  bool _loading = false;
  bool _playing = false;
  int? _stopAtMs;
  int _posMs = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    // 소리 주소를 여는 데 1~2초 걸리므로, 구간 미리보기가 나타날 때 미리 열어 둔다(재생은 하지 않는다).
    if (widget.audioUrl != null) {
      unawaited(_prepare().catchError((Object _) {}));
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player?.dispose();
    super.dispose();
  }

  /// 플레이어를 만들고 소리 주소를 열어 둔다. 한 번만 하고, 실패하면 다음에 다시 시도한다.
  Future<void> _prepare() {
    return _prepared ??= () async {
      try {
        final p = _ensurePlayer();
        await p.setReleaseMode(ReleaseMode.stop);
        await p.setSource(UrlSource(widget.audioUrl!));
      } catch (_) {
        _prepared = null;
        rethrow;
      }
    }();
  }

  AudioPlayer _ensurePlayer() {
    final existing = _player;
    if (existing != null) return existing;
    final p = _player = AudioPlayer();
    _subs.add(p.onPositionChanged.listen(_onPosition));
    _subs.add(
      p.onPlayerStateChanged.listen((s) {
        if (!mounted) return;
        setState(() {
          _playing = s == PlayerState.playing;
          if (_playing) _loading = false;
        });
      }),
    );
    _subs.add(
      p.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      }),
    );
    return p;
  }

  void _onPosition(Duration d) {
    if (!mounted) return;
    final ms = d.inMilliseconds;
    final stop = _stopAtMs;
    if (stop != null && ms >= stop) {
      _stopAtMs = null;
      _player?.pause();
      setState(() => _posMs = stop);
      return;
    }
    setState(() => _posMs = ms);
  }

  /// [fromSec]~[toSec] 만 듣고 자동으로 멈춘다.
  Future<void> _play(int fromSec, int toSec) async {
    final url = widget.audioUrl;
    if (url == null || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _prepare();
      final p = _ensurePlayer();
      _stopAtMs = null;
      await p.pause();
      await p.seek(Duration(seconds: fromSec));
      _stopAtMs = toSec * 1000;
      await p.resume();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '소리를 불러오지 못했어요. 영상을 다시 조회하면 될 수 있어요.';
        });
      }
    }
  }

  Future<void> _stop() async {
    _stopAtMs = null;
    await _player?.pause();
  }

  @override
  Widget build(BuildContext context) {
    final board = widget.storyboard;
    final hasAudio = widget.audioUrl != null;
    if (board == null && !hasAudio) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant);
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
        if (hasAudio) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: widget.enabled && !_loading ? () => _play(s, e) : null,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('선택 구간 듣기'),
              ),
              FilledButton.tonalIcon(
                onPressed: widget.enabled && !_loading
                    ? () => _play(s, (s + _peekSec).clamp(s, e))
                    : null,
                icon: const Icon(Icons.skip_previous),
                label: const Text('시작 부분'),
              ),
              FilledButton.tonalIcon(
                onPressed: widget.enabled && !_loading
                    ? () => _play((e - _peekSec).clamp(s, e), e)
                    : null,
                icon: const Icon(Icons.skip_next),
                label: const Text('끝 부분'),
              ),
              if (_playing)
                OutlinedButton.icon(
                  onPressed: _stop,
                  icon: const Icon(Icons.pause),
                  label: Text('정지 ${formatMs(_posMs)}'),
                )
              else if (_loading)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text('불러오는 중…', style: small),
                  ],
                ),
            ],
          ),
        ],
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
        Text(label, style: theme.textTheme.labelMedium?.copyWith(color: colors.primary)),
      ],
    );
  }
}

/// 스토리보드 그림에서 [seconds] 시각의 장면 한 칸만 잘라서 보여 준다.
class StoryboardFrameView extends StatelessWidget {
  const StoryboardFrameView({super.key, required this.board, required this.seconds});

  final Storyboard board;
  final double seconds;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final f = board.frameAt(seconds);
    // 격자 안의 칸 위치를 Align 의 -1~1 좌표로 바꾼다(칸이 하나면 가운데).
    double axis(int index, int count) => count <= 1 ? 0 : -1 + 2 * index / (count - 1);

    final placeholder = ColoredBox(
      color: colors.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.image_outlined, color: colors.outline),
      ),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        placeholder,
        FittedBox(
          fit: BoxFit.cover,
          clipBehavior: Clip.hardEdge,
          child: ClipRect(
            child: Align(
              alignment: Alignment(axis(f.column, f.columns), axis(f.row, f.rows)),
              widthFactor: 1 / f.columns,
              heightFactor: 1 / f.rows,
              child: Image.network(
                f.url,
                // 같은 그림 한 장에서 여러 칸을 쓰므로 바뀔 때 깜빡이지 않게 이전 그림을 유지한다.
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
