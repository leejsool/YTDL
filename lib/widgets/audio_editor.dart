import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../backend/backend.dart';
import '../models.dart';
import '../util/names.dart';
import '../util/time_format.dart';

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

  SavedAudio get _a => widget.audio;

  @override
  void initState() {
    super.initState();
    _subs.add(_player.onDurationChanged.listen((d) => _setDuration(d.inMilliseconds)));
    _subs.add(_player.onPositionChanged.listen(_onPosition));
    _subs.add(_player.onPlayerStateChanged.listen((s) {
      if (mounted && !_priming) setState(() => _playing = s == PlayerState.playing);
    }));
    _subs.add(_player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    }));
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
          _error = '재생할 수 없습니다: ${e.toString().replaceFirst('Exception: ', '')}';
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
        _selEnd = _selEnd.clamp(_minSelMs, ms);
        _selStart = _selStart.clamp(0, _selEnd - _minSelMs);
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
      _selStart = start.clamp(0, _durMs - _minSelMs);
      _selEnd = end.clamp(_selStart + _minSelMs, _durMs);
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

  Future<void> _save() async {
    if (_saving || _isFull) return;
    final startSrc = _a.srcStart + _selStart / 1000;
    final endSrc = _a.srcStart + _selEnd / 1000;
    final name = '${_a.title}${cutSuffix(startSrc, endSrc)}';
    setState(() {
      _saving = true;
      _saveError = null;
    });
    await _player.pause();
    try {
      final r = await widget.backend.trimAudio(_a.path, _selStart / 1000, _selEnd / 1000, name);
      if (!mounted) return;
      final path = r.filePath;
      if (path == null) throw Exception('저장된 파일 경로를 알 수 없습니다.');
      widget.onSaved(SavedAudio(
        title: _a.title,
        path: path,
        location: r.location,
        srcStart: startSrc,
        srcEnd: endSrc,
        // 일반 파일에서 처음 잘랐다면, 이제부터 "처음 연 파일"이 원본이 된다.
        sourceLabel: _a.sourceLabel ?? '원본 파일',
      ));
    } catch (e) {
      if (mounted) {
        setState(() => _saveError = e.toString().replaceFirst('Exception: ', ''));
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

    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.headphones),
              const SizedBox(width: 8),
              Text('미리듣기 · 다듬기', style: theme.textTheme.titleMedium),
            ]),
            if (widget.note != null) ...[
              const SizedBox(height: 8),
              Text(widget.note!, style: TextStyle(color: theme.colorScheme.primary)),
            ],
            const SizedBox(height: 8),
            SelectableText(baseNameOf(_a.path), style: small),
            if (_a.sourceLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                '이 파일 = ${_a.sourceLabel} ${_src(_a.srcStart)} ~ ${_src(_a.srcEnd)} 구간',
                style: theme.textTheme.titleSmall,
              ),
            ],
            const SizedBox(height: 12),
            if (_loading) const LinearProgressIndicator(),
            if (_error != null) Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
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

    return [
      // 재생 막대
      Row(children: [
        IconButton.filled(
          tooltip: _playing ? '일시정지' : '재생',
          onPressed: _saving ? null : _togglePlay,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
        ),
        Expanded(
          child: Slider(
            min: 0,
            max: _durMs.toDouble(),
            value: _posMs.clamp(0, _durMs).toDouble(),
            onChangeStart: (_) => _dragging = true,
            onChanged: (v) => setState(() => _posMs = v.round()),
            onChangeEnd: (v) async {
              _dragging = false;
              _stopAtMs = null;
              await _seek(v.round());
            },
          ),
        ),
      ]),
      Padding(
        padding: const EdgeInsets.only(left: 8),
        child: Text(
          _a.sourceLabel == null
              ? '${formatMs(_posMs)} / ${formatMs(_durMs)}'
              : '${formatMs(_posMs)} / ${formatMs(_durMs)}   ·   ${_a.sourceLabel} 기준 ${_src(posSrc)}',
          style: small,
        ),
      ),
      const Divider(height: 28),

      // 자를 구간
      Text('자를 구간 고르기', style: theme.textTheme.titleSmall),
      RangeSlider(
        min: 0,
        max: _durMs.toDouble(),
        values: RangeValues(_selStart.toDouble(), _selEnd.toDouble()),
        labels: RangeLabels(formatMs(_selStart), formatMs(_selEnd)),
        onChanged: _saving
            ? null
            : (v) {
                final movedStart = v.start.round() != _selStart;
                var s = v.start.round();
                var e = v.end.round();
                if (e - s < _minSelMs) {
                  if (movedStart) {
                    s = e - _minSelMs;
                  } else {
                    e = s + _minSelMs;
                  }
                }
                _setSel(s, e);
              },
      ),
      Row(children: [
        _timeField('시작', _startCtl),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('~')),
        _timeField('끝', _endCtl),
      ]),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 4, children: [
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
      ]),
      const SizedBox(height: 4),
      Text('재생하다가 멈춘 위치를 "여기부터 / 여기까지"로 잡을 수 있어요.', style: small),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 4, children: [
        FilledButton.tonalIcon(
          onPressed: _saving ? null : () => _playRange(_selStart, _selEnd),
          icon: const Icon(Icons.play_circle_outline),
          label: const Text('선택 구간 듣기'),
        ),
        FilledButton.tonalIcon(
          onPressed: _saving
              ? null
              : () => _playRange(_selStart, (_selStart + _peekMs).clamp(0, _selEnd)),
          icon: const Icon(Icons.skip_previous),
          label: const Text('시작 부분'),
        ),
        FilledButton.tonalIcon(
          onPressed: _saving
              ? null
              : () => _playRange((_selEnd - _peekMs).clamp(_selStart, _selEnd), _selEnd),
          icon: const Icon(Icons.skip_next),
          label: const Text('끝 부분'),
        ),
      ]),
      const SizedBox(height: 16),
      Text(
        '선택: 이 파일 ${formatMs(_selStart)} ~ ${formatMs(_selEnd)}  (${selLen.toStringAsFixed(1)}초)'
        '${_a.sourceLabel == null ? '' : '\n→ ${_a.sourceLabel} ${_src(srcStart)} ~ ${_src(srcEnd)}'}',
        style: theme.textTheme.bodyMedium,
      ),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: (_saving || _isFull) ? null : _save,
        icon: _saving
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.content_cut),
        label: Text(_isFull ? '자를 구간을 먼저 골라 주세요' : '선택 구간만 새 파일로 저장'),
      ),
      if (!_isFull)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text('지금 파일은 그대로 두고, 잘라낸 부분을 새 파일로 저장해요.', style: small),
        ),
      if (_saveError != null)
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(_saveError!, style: TextStyle(color: theme.colorScheme.error)),
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
