import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../backend/backend.dart';
import '../models.dart';
import '../util/names.dart';
import '../util/time_format.dart';
import 'range_transport_bar.dart';
import 'trim_selector.dart';
import 'rocker_switch.dart';

/// 영상 파일을 보면서 들어 보고, 구간을 골라 새 영상 파일로 저장하는 카드.
/// (음원 편집기와 같은 흐름. 저장 결과는 [onSaved] 로 부모에게 알려 새 편집 대상이 된다.)
class VideoEditor extends StatefulWidget {
  const VideoEditor({
    super.key,
    required this.backend,
    required this.video,
    required this.onSaved,
    this.note,
    this.active = true,
    this.defaultReencode = false,
  });

  final Backend backend;

  /// 편집할 영상. (이름이 SavedAudio 지만 음원·영상 공용으로 쓰는 "파일 정보"다.)
  final SavedAudio video;
  final void Function(SavedAudio saved) onSaved;
  final String? note;

  /// 이 편집기가 화면에 보이는 탭인지. 다른 탭으로 가면 재생을 멈춘다.
  final bool active;

  /// 저장 방식의 처음 선택(옵션 탭의 기본값). false = 빠르게, true = 정확하게.
  final bool defaultReencode;

  @override
  State<VideoEditor> createState() => _VideoEditorState();
}

class _VideoEditorState extends State<VideoEditor> {
  static const _peekMs = 3000;

  VideoPlayerController? _c;
  bool _loading = true;
  String? _error;
  int _durSec = 0;
  int _posMs = 0;
  bool _playing = false;
  bool _dragging = false;
  int? _stopAtMs; // 이 시각에 도달하면 자동으로 멈춘다(구간 듣기용)

  int _selStart = 0;
  int _selEnd = 0;

  late bool _reencode = widget.defaultReencode;
  bool _saving = false;
  String? _saveError;

  SavedAudio get _v => widget.video;
  bool get _isFull => _selStart <= 0 && _selEnd >= _durSec;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void didUpdateWidget(VideoEditor old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active && _playing) {
      _stopAtMs = null;
      _c?.pause();
    }
  }

  @override
  void dispose() {
    _c?.removeListener(_tick);
    _c?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final c = VideoPlayerController.file(File(_v.path));
    try {
      await c.initialize();
      await c.setLooping(false);
      if (!mounted) {
        await c.dispose();
        return;
      }
      c.addListener(_tick);
      final dur = (c.value.duration.inMilliseconds / 1000).ceil();
      setState(() {
        _c = c;
        _durSec = dur;
        _selStart = 0;
        _selEnd = dur;
        _loading = false;
      });
    } catch (e) {
      await c.dispose();
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              '재생할 수 없습니다: ${e.toString().replaceFirst('Exception: ', '')}';
        });
      }
    }
  }

  void _tick() {
    final c = _c;
    if (c == null || !mounted) return;
    final v = c.value;
    final ms = v.position.inMilliseconds;
    final stop = _stopAtMs;
    if (stop != null && v.isPlaying && ms >= stop) {
      _stopAtMs = null;
      c.pause();
      c.seekTo(Duration(milliseconds: stop));
      setState(() {
        _posMs = stop;
        _playing = false;
      });
      return;
    }
    final ended = v.duration > Duration.zero && v.position >= v.duration;
    setState(() {
      if (!_dragging) _posMs = ms;
      _playing = v.isPlaying && !ended;
    });
  }

  // ------------------------------------------------------------------ 재생
  Future<void> _togglePlay() async {
    final c = _c;
    if (c == null) return;
    _stopAtMs = null;
    if (_playing) {
      await c.pause();
      return;
    }
    if (_posMs >= _durSec * 1000 - 100) await c.seekTo(Duration.zero);
    await c.play();
  }

  Future<void> _seek(int ms) async {
    final c = _c;
    if (c == null) return;
    ms = ms.clamp(0, _durSec * 1000);
    await c.seekTo(Duration(milliseconds: ms));
    if (mounted) setState(() => _posMs = ms);
  }

  /// 가운데 재생 버튼: 재생 중이면 멈춘다. 아니면 선택 구간을 본다
  /// (재생 위치가 구간 안이면 거기서부터 구간 끝까지, 밖이면 구간 처음부터).
  Future<void> _playSelection() async {
    if (_playing) {
      await _togglePlay();
      return;
    }
    final s = _selStart * 1000;
    final e = _selEnd * 1000;
    final inside = _posMs >= s && _posMs < e - 100;
    await _playRange(inside ? _posMs : s, e);
  }

  /// [fromMs]~[toMs] 만 재생하고 자동으로 멈춘다.
  Future<void> _playRange(int fromMs, int toMs) async {
    final c = _c;
    if (c == null) return;
    await c.pause();
    _stopAtMs = null;
    await _seek(fromMs);
    _stopAtMs = toMs;
    await c.play();
  }

  // ------------------------------------------------------------------ 구간
  void _setSel(int s, int e) {
    setState(() {
      _selStart = s.clamp(0, _durSec - 1);
      _selEnd = e.clamp(_selStart + 1, _durSec);
      _saveError = null;
    });
  }

  // ------------------------------------------------------------------ 저장
  Future<void> _save() async {
    if (_saving || _isFull) return;
    final startSrc = _v.srcStart + _selStart;
    final endSrc = _v.srcStart + _selEnd;
    final name = '${_v.title}${cutSuffix(startSrc, endSrc)}';
    setState(() {
      _saving = true;
      _saveError = null;
    });
    await _c?.pause();
    try {
      final r = await widget.backend.trimVideo(
        _v.path,
        _selStart.toDouble(),
        _selEnd.toDouble(),
        name,
        reencode: _reencode,
      );
      final path = r.filePath;
      if (!mounted) return;
      if (path == null) {
        setState(() => _saveError = '저장은 했지만 파일 경로를 알 수 없습니다: ${r.location}');
        return;
      }
      widget.onSaved(
        SavedAudio(
          title: _v.title,
          path: path,
          location: r.location,
          srcStart: startSrc.toDouble(),
          srcEnd: endSrc.toDouble(),
          sourceLabel: _v.sourceLabel ?? '원본 파일',
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(
          () => _saveError = e.toString().replaceFirst('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final small = theme.textTheme.bodySmall?.copyWith(
      color: colors.onSurfaceVariant,
    );
    final c = _c;
    final ready = !_loading && _error == null && c != null && _durSec > 0;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.note != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  widget.note!,
                  style: TextStyle(color: colors.primary),
                ),
              ),
            Row(
              children: [
                Icon(Icons.movie_outlined, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    baseNameOf(_v.path),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Text(_error!, style: TextStyle(color: colors.error))
            else if (c != null && ready) ...[
              _buildScreen(c, colors),
              _buildSeekBar(small),
              const SizedBox(height: 4),
              RangeTransportBar(
                enabled: !_saving,
                playing: _playing,
                onSetStart: () => _setSel((_posMs / 1000).floor(), _selEnd),
                onPlayStartPart: () => _playRange(
                  _selStart * 1000,
                  (_selStart * 1000 + _peekMs).clamp(
                    _selStart * 1000,
                    _selEnd * 1000,
                  ),
                ),
                onPlayPause: _playSelection,
                onPlayEndPart: () => _playRange(
                  (_selEnd * 1000 - _peekMs).clamp(
                    _selStart * 1000,
                    _selEnd * 1000,
                  ),
                  _selEnd * 1000,
                ),
                onSetEnd: () => _setSel(_selStart, (_posMs / 1000).ceil()),
              ),
              const SizedBox(height: 4),
              Text('맨 왼쪽 버튼은 지금 위치를 시작으로, 맨 오른쪽 버튼은 끝으로 잡아요.', style: small),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: colors.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TrimSelector(
                      duration: _durSec,
                      start: _selStart,
                      end: _selEnd,
                      enabled: !_saving,
                      onChanged: _setSel,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Text('저장 방식', style: theme.textTheme.titleSmall),
              const SizedBox(height: 6),
              RockerSwitch<bool>(
                left: const RockerOption(
                  value: false,
                  label: '빠르게',
                  icon: Icons.bolt,
                ),
                right: const RockerOption(
                  value: true,
                  label: '정확하게',
                  icon: Icons.gps_fixed,
                ),
                value: _reencode,
                enabled: !_saving,
                onChanged: (v) => setState(() => _reencode = v),
              ),
              const SizedBox(height: 6),
              Text(
                _reencode
                    ? '화면과 소리를 다시 만들어 정한 시각에서 정확히 시작해요. 시간이 더 걸리고 MP4로 저장돼요.'
                    : '화면과 소리를 그대로 복사해서 빠르고 화질 손실이 없어요. 대신 시작 지점이 바로 앞 장면(키프레임)으로 조금 당겨질 수 있어요.',
                style: small,
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: (_saving || _isFull) ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.content_cut),
                label: Text(
                  _saving
                      ? (_reencode ? '다시 인코딩하는 중… (영상이 길면 오래 걸려요)' : '저장하는 중…')
                      : _isFull
                      ? '구간을 고르면 저장할 수 있어요'
                      : '선택 구간 새 파일로 저장 (${formatSeconds(_selEnd - _selStart)})',
                ),
              ),
              const SizedBox(height: 4),
              Text(
                Platform.isAndroid
                    ? '저장 위치: Movies/${widget.backend.folderName} (원본은 그대로 남아요)'
                    : '저장 위치: 원본 파일과 같은 폴더 (원본은 그대로 남아요)',
                style: small,
              ),
              if (_saveError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    _saveError!,
                    style: TextStyle(color: colors.error),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildScreen(VideoPlayerController c, ColorScheme colors) {
    final ratio = c.value.aspectRatio > 0 ? c.value.aspectRatio : 16 / 9;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: AspectRatio(
          aspectRatio: ratio,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: GestureDetector(
              onTap: _togglePlay,
              child: ColoredBox(
                color: Colors.black,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoPlayer(c),
                    if (!_playing)
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill,
                          size: 56,
                          color: Colors.white70,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSeekBar(TextStyle? small) {
    final max = (_durSec * 1000).toDouble();
    return Column(
      children: [
        Slider(
          value: _posMs.toDouble().clamp(0, max),
          max: max,
          onChangeStart: (_) => _dragging = true,
          onChanged: (v) => setState(() => _posMs = v.round()),
          onChangeEnd: (v) async {
            _stopAtMs = null;
            await _seek(v.round());
            _dragging = false;
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatMs(_posMs), style: small),
              Text(formatSeconds(_durSec), style: small),
            ],
          ),
        ),
      ],
    );
  }
}
