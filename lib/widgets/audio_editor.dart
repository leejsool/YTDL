import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../models.dart';
import '../util/names.dart';
import '../util/time_format.dart';
import 'gain_selector.dart';
import 'trim_selector.dart';

/// 받은 음원을 앱 안에서 들어 보고, 원본 영상 기준 어디서 어디까지인지 확인하고,
/// 더 자를 구간을 골라 새 파일로 저장하는 카드.
class AudioEditor extends StatefulWidget {
  const AudioEditor({
    super.key,
    required this.backend,
    required this.audio,
    required this.onSaved,
    this.note,
    this.active = true,
  });

  final Backend backend;
  final SavedAudio audio;

  /// 이 편집기가 화면에 보이는 탭인지. 다른 탭으로 가면 재생을 멈춘다.
  final bool active;

  /// 새 파일로 저장했을 때 호출. 부모가 [audio] 를 새 파일로 바꿔 준다.
  final void Function(SavedAudio saved) onSaved;

  /// 카드 위에 보여 줄 안내(예: 방금 새 파일로 저장했다는 알림).
  final String? note;

  @override
  State<AudioEditor> createState() => _AudioEditorState();
}

class _AudioEditorState extends State<AudioEditor> {
  /// 시작/끝 부분 듣기 길이
  static const _peekMs = 2000;
  static const _minSelMs = 100;

  final AudioPlayer _player = AudioPlayer();
  final List<StreamSubscription<dynamic>> _subs = [];
  final _startCtl = TextEditingController();
  final _endCtl = TextEditingController();

  bool _loading = true;
  String? _error;
  int _durMs = 0;
  int _posMs = 0;
  bool _playing = false;
  bool _dragging = false;
  int? _stopAtMs; // 이 시각에 도달하면 자동으로 멈춘다(구간 듣기용)

  int _selStart = 0;
  int _selEnd = 0;

  bool _saving = false;
  String? _saveError;
  AudioGain _gain = const AudioGain.none();

  SavedAudio get _a => widget.audio;
  int get _minSpan => _durMs < _minSelMs ? _durMs : _minSelMs;

  @override
  void initState() {
    super.initState();
    _subs.add(
      _player.onDurationChanged.listen((d) => _setDuration(d.inMilliseconds)),
    );
    _subs.add(_player.onPositionChanged.listen(_onPosition));
    _subs.add(
      _player.onPlayerStateChanged.listen((s) {
        if (mounted && !_priming) {
          setState(() => _playing = s == PlayerState.playing);
        }
      }),
    );
    _subs.add(
      _player.onPlayerComplete.listen((_) {
        if (mounted) setState(() => _playing = false);
      }),
    );
    _load();
  }

  @override
  void didUpdateWidget(AudioEditor old) {
    super.didUpdateWidget(old);
    if (old.active && !widget.active && _playing) {
      _stopAtMs = null;
      _player.pause();
    }
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _player.dispose();
    _startCtl.dispose();
    _endCtl.dispose();
    super.dispose();
  }

  /// 실험용: 파일을 연 직후 소리 없이(볼륨 0) 잠깐 재생했다가 처음으로 되돌려 첫 재생 지연을 줄여 본다.
  /// Windows 에서 측정해 보니 효과가 없어서(첫 재생 지연 144ms → 157ms) 기본은 꺼 둔다.
  /// 첫 재생이 두두둑 끊기는 현상(Windows)에도 효과가 없었다 — 원인은 앱이 아니라 Realtek "오디오 향상"이었다
  /// (Windows 설정 → 시스템 → 소리 → 출력 → 해당 장치 → 오디오 향상 끔). 무음을 계속 재생해 장치를 깨워 두는 것도 소용없었다.
  /// Android 실기기에서 효과가 확인되면 켠다:  flutter build apk --dart-define=PRIME=true
  static const _primeEnabled = bool.fromEnvironment('PRIME');
  bool _priming = false;

  Future<void> _prime() async {
    if (!_primeEnabled) return;
    _priming = true;
    try {
      await _player.setVolume(0);
      await _player.resume();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _player.pause();
      await _player.seek(Duration.zero);
    } finally {
      await _player.setVolume(1);
      _priming = false;
      _stopAtMs = null;
    }
  }

  Future<void> _load() async {
    try {
      await _player.setReleaseMode(ReleaseMode.stop);
      await _player.setSource(DeviceFileSource(_a.path));
      final d = await _player.getDuration();
      if (d != null) _setDuration(d.inMilliseconds);
      await _prime();
      if (mounted) {
        setState(() {
          _loading = false;
          _posMs = 0;
          _playing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error =
              '재생할 수 없습니다: ${e.toString().replaceFirst('Exception: ', '')}';
        });
      }
    }
  }

  void _setDuration(int ms) {
    if (!mounted || ms <= 0 || ms == _durMs) return;
    setState(() {
      final first = _durMs == 0;
      _durMs = ms;
      if (first) {
        _selStart = 0;
        _selEnd = ms;
        _syncFields();
      } else {
        _selEnd = _selEnd.clamp(_minSpan, ms);
        _selStart = _selStart.clamp(0, _selEnd - _minSpan);
        _syncFields();
      }
    });
  }

  void _onPosition(Duration p) {
    if (!mounted || _priming) return;
    final ms = p.inMilliseconds;
    final stop = _stopAtMs;
    if (stop != null && ms >= stop) {
      _stopAtMs = null;
      _player.pause();
      _player.seek(Duration(milliseconds: stop));
      setState(() => _posMs = stop);
      return;
    }
    if (!_dragging) setState(() => _posMs = ms);
  }

  void _syncFields() {
    _startCtl.text = formatMs(_selStart);
    _endCtl.text = formatMs(_selEnd);
  }

  // ------------------------------------------------------------------ 재생
  Future<void> _togglePlay() async {
    _stopAtMs = null;
    if (_playing) {
      await _player.pause();
      return;
    }
    // 끝까지 들었거나 끝에 있으면 처음부터
    if (_posMs >= _durMs - 50) await _seek(0);
    await _player.resume();
  }

  Future<void> _seek(int ms) async {
    ms = ms.clamp(0, _durMs);
    await _player.seek(Duration(milliseconds: ms));
    if (mounted) setState(() => _posMs = ms);
  }

  /// [fromMs]~[toMs] 만 재생하고 자동으로 멈춘다.
  Future<void> _playRange(int fromMs, int toMs) async {
    await _player.pause();
    _stopAtMs = null;
    await _seek(fromMs);
    _stopAtMs = toMs;
    await _player.resume();
  }

  // ------------------------------------------------------------------ 구간
  void _setSel(int start, int end, {bool fromText = false}) {
    setState(() {
      _selStart = start.clamp(0, _durMs - _minSpan);
      _selEnd = end.clamp(_selStart + _minSpan, _durMs);
      if (!fromText) {
        _syncFields();
      }
      _saveError = null;
    });
  }

  void _commitText() {
    final s = parseMs(_startCtl.text) ?? _selStart;
    final e = parseMs(_endCtl.text) ?? _selEnd;
    _setSel(s, e);
    _syncFields();
  }

  bool get _isFull => _selStart <= 0 && _selEnd >= _durMs - 20;

  /// 구간을 안 자르고 음량만 바꿔 저장하는 경우인지.
  bool get _gainOnly => _isFull && _gain.isActive;

  Future<void> _save() async {
    if (_saving || (_isFull && !_gain.isActive)) return;
    final startSrc = _a.srcStart + _selStart / 1000;
    final endSrc = _a.srcStart + _selEnd / 1000;
    // 원본 영상 기준 구간 표시는 다시 열었을 때 구간을 이어받는 데 쓰이므로, 원본과의 대응이 있는 파일은
    // 전체를 저장할 때도 붙인다. 아무 정보 없는 일반 파일을 음량만 바꿀 때는 붙이지 않는다.
    final withCut = !_isFull || _a.sourceLabel != null;
    final name =
        '${_a.title}${_gain.nameTag}${withCut ? cutSuffix(startSrc, endSrc) : ''}';
    setState(() {
      _saving = true;
      _saveError = null;
    });
    await _player.pause();
    try {
      final r = await widget.backend.trimAudio(
        _a.path,
        _selStart / 1000,
        _selEnd / 1000,
        name,
        gain: _gain,
      );
      if (!mounted) return;
      final path = r.filePath;
      if (path == null) throw Exception('저장된 파일 경로를 알 수 없습니다.');
      widget.onSaved(
        SavedAudio(
          title: _a.title,
          path: path,
          location: r.location,
          srcStart: startSrc,
          srcEnd: endSrc,
          // 일반 파일에서 처음 잘랐다면, 이제부터 "처음 연 파일"이 원본이 된다.
          sourceLabel: _a.sourceLabel ?? '원본 파일',
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

  // ------------------------------------------------------------------ UI
  String _src(num seconds) => formatMs((seconds * 1000).round());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final ready = !_loading && _error == null && _durMs > 0;
    final colors = theme.colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.secondaryContainer,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(Icons.music_note, color: colors.primary),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText(
                        baseNameOf(_a.path),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '미리듣기 · 다듬기',
                        style: small?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (widget.note != null) ...[
              const SizedBox(height: 8),
              Text(
                widget.note!,
                style: TextStyle(color: theme.colorScheme.primary),
              ),
            ],
            if (_a.sourceLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                '이 파일 = ${_a.sourceLabel} ${_src(_a.srcStart)} ~ ${_src(_a.srcEnd)} 구간',
                style: theme.textTheme.titleSmall,
              ),
            ],
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null)
              Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
            if (ready) ..._buildPlayer(theme),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPlayer(ThemeData theme) {
    final small = theme.textTheme.bodySmall;
    final selLen = (_selEnd - _selStart) / 1000;
    final srcStart = _a.srcStart + _selStart / 1000;
    final srcEnd = _a.srcStart + _selEnd / 1000;
    final posSrc = _a.srcStart + _posMs / 1000;
    final colors = theme.colorScheme;

    return [
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
            Row(
              children: [
                DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.outlineVariant),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [colors.surface, colors.surfaceContainerHighest],
                    ),
                  ),
                  child: IconButton(
                    tooltip: _playing ? '일시정지' : '재생',
                    color: colors.primary,
                    onPressed: _saving ? null : _togglePlay,
                    icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
                  ),
                ),
                Expanded(
                  child: Slider(
                    max: _durMs.toDouble(),
                    value: _posMs.clamp(0, _durMs).toDouble(),
                    onChangeStart: (_) => _dragging = true,
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _posMs = v.round()),
                    onChangeEnd: (v) async {
                      _dragging = false;
                      _stopAtMs = null;
                      await _seek(v.round());
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(
              '${formatMs(_posMs)} / ${formatMs(_durMs)}'
              '${_a.sourceLabel == null ? '' : '   ·   ${_a.sourceLabel} 기준 ${_src(posSrc)}'}',
              style: small,
            ),
          ],
        ),
      ),
      const SizedBox(height: 17),

      // 자를 구간
      Row(
        children: [
          Icon(Icons.content_cut, size: 17, color: colors.primary),
          const SizedBox(width: 7),
          Text('구간 자르기', style: theme.textTheme.titleSmall),
        ],
      ),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colors.surfaceContainerLow,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: colors.outlineVariant),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _timeField('시작', _startCtl),
                const SizedBox(width: 12),
                _timeField('끝', _endCtl),
              ],
            ),
            CutRangeSlider(
              max: _durMs.toDouble(),
              values: RangeValues(_selStart.toDouble(), _selEnd.toDouble()),
              format: (t) => formatMs(t.round()),
              onChanged: _saving
                  ? null
                  : (v) {
                      var start = v.start.round();
                      var end = v.end.round();
                      if (end - start < _minSpan) {
                        if (start != _selStart) {
                          start = end - _minSpan;
                        } else {
                          end = start + _minSpan;
                        }
                      }
                      _setSel(start, end);
                    },
            ),
          ],
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _setSel(_posMs, _selEnd),
            icon: const Icon(Icons.first_page),
            label: const Text('여기부터'),
          ),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _setSel(_selStart, _posMs),
            icon: const Icon(Icons.last_page),
            label: const Text('여기까지'),
          ),
        ],
      ),
      const SizedBox(height: 4),
      Text('재생하다가 멈춘 위치를 "여기부터 / 여기까지"로 잡을 수 있어요.', style: small),
      const SizedBox(height: 12),
      Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          FilledButton.tonalIcon(
            onPressed: _saving ? null : () => _playRange(_selStart, _selEnd),
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('선택 구간 듣기'),
          ),
          FilledButton.tonalIcon(
            onPressed: _saving
                ? null
                : () => _playRange(
                    _selStart,
                    (_selStart + _peekMs).clamp(0, _selEnd),
                  ),
            icon: const Icon(Icons.skip_previous),
            label: const Text('시작 부분'),
          ),
          FilledButton.tonalIcon(
            onPressed: _saving
                ? null
                : () => _playRange(
                    (_selEnd - _peekMs).clamp(_selStart, _selEnd),
                    _selEnd,
                  ),
            icon: const Icon(Icons.skip_next),
            label: const Text('끝 부분'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Text(
        '선택: 이 파일 ${formatMs(_selStart)} ~ ${formatMs(_selEnd)}  (${selLen.toStringAsFixed(1)}초)'
        '${_a.sourceLabel == null ? '' : '\n→ ${_a.sourceLabel} ${_src(srcStart)} ~ ${_src(srcEnd)}'}',
        style: theme.textTheme.bodyMedium,
      ),
      const Divider(height: 28),

      // 음량 조절
      Text('음량 조절', style: theme.textTheme.titleSmall),
      const SizedBox(height: 4),
      GainSelector(
        value: _gain,
        enabled: !_saving,
        analysisSource: (_a.path, _selStart, _selEnd),
        onAuto: (token) => widget.backend.measureGain(
          _a.path,
          token,
          startSec: _selStart / 1000,
          endSec: _selEnd / 1000,
        ),
        onChanged: (g) => setState(() {
          _gain = g;
          _saveError = null;
        }),
      ),
      const SizedBox(height: 4),
      Text(
        '미리듣기는 파일 그대로의 소리예요. 음량은 저장한 새 파일을 열어서 확인해 보세요(원본은 그대로 남아요).',
        style: small,
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: (_saving || (_isFull && !_gain.isActive)) ? null : _save,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(
                _gainOnly || (!_isFull && _gain.isActive)
                    ? Icons.volume_up
                    : Icons.content_cut,
              ),
        label: Text(
          _saving
              ? (_gain.isActive ? '음량 조절하며 저장하는 중…' : '저장하는 중…')
              : _isFull
              ? (_gain.isActive ? '음량을 바꿔 새 파일로 저장' : '자를 구간을 먼저 골라 주세요')
              : (_gain.isActive ? '선택 구간을 음량 바꿔 새 파일로 저장' : '선택 구간만 새 파일로 저장'),
        ),
      ),
      if (!_isFull || _gain.isActive)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            _gainOnly
                ? '지금 파일은 그대로 두고, 음량을 바꾼 파일을 새로 저장해요.'
                : '지금 파일은 그대로 두고, 잘라낸 부분을 새 파일로 저장해요.',
            style: small,
          ),
        ),
      if (_saveError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            _saveError!,
            style: TextStyle(color: theme.colorScheme.error),
          ),
        ),
    ];
  }

  Widget _timeField(String label, TextEditingController c) {
    return Expanded(
      child: TextField(
        controller: c,
        enabled: !_saving,
        keyboardType: TextInputType.datetime,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onSubmitted: (_) => _commitText(),
        onTapOutside: (_) => _commitText(),
      ),
    );
  }
}
