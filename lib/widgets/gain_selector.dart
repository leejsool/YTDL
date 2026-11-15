import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';

class GainSelector extends StatefulWidget {
  const GainSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onAuto,
    required this.analysisSource,
    this.enabled = true,
  });

  final AudioGain value;
  final ValueChanged<AudioGain> onChanged;
  final Future<double> Function(CancelToken token) onAuto;
  final Object analysisSource;
  final bool enabled;

  static const minDb = -12;
  static const maxDb = 20;

  @override
  State<GainSelector> createState() => _GainSelectorState();
}

class _GainSelectorState extends State<GainSelector> {
  static const _size = 112.0;
  static const _arc = math.pi * 1.5;
  static const _start = math.pi * .75;
  static const _turn = math.pi * 2;
  static const _min = GainSelector.minDb;
  static const _max = GainSelector.maxDb;

  final _focus = FocusNode();
  CancelToken? _pending;
  String? _status;
  bool _error = false;
  bool _focused = false;
  bool _vertical = false;
  double _previousAngle = 0;
  double _dragValue = 0;

  int get _db => widget.value.db.round().clamp(_min, _max);
  String get _dbLabel => _label(_db);
  String _label(int db) => db >= 0 ? '+$db' : '−${-db}';

  @override
  void didUpdateWidget(GainSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.analysisSource != widget.analysisSource || !widget.enabled) {
      _cancel();
    }
  }

  @override
  void dispose() {
    _pending?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _cancel() {
    _pending?.cancel();
    _pending = null;
    _status = null;
    _error = false;
  }

  void _setDb(num value) {
    final next = value.round().clamp(_min, _max);
    if (_pending != null || _status != null) setState(_cancel);
    if (next != _db) widget.onChanged(AudioGain.manual(next.toDouble()));
  }

  Future<void> _auto() async {
    if (_pending != null) {
      setState(_cancel);
      return;
    }
    final token = CancelToken();
    setState(() {
      _pending = token;
      _status = '음량을 분석하는 중…';
      _error = false;
    });
    try {
      final measured = await widget.onAuto(token);
      if (!mounted || _pending != token) return;
      final gain = measured.round().clamp(_min, _max);
      setState(() {
        _pending = null;
        _status = '자동 적용됨';
      });
      widget.onChanged(AudioGain.manual(gain.toDouble()));
    } catch (e) {
      if (!mounted || _pending != token) return;
      setState(() {
        _pending = null;
        _error = true;
        _status = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Offset _offset(Offset position) =>
      position - const Offset(_size / 2, _size / 2);

  double _dbAt(double angle) {
    var distance = (angle - _start) % _turn;
    if (distance > _arc) {
      distance = distance - _arc < _turn - distance ? _arc : 0;
    }
    return _min + distance / _arc * (_max - _min);
  }

  void _startDrag(DragStartDetails details) {
    _focus.requestFocus();
    final point = _offset(details.localPosition);
    _vertical = point.distance < _size * .29;
    _previousAngle = point.direction;
    _dragValue = _vertical ? _db.toDouble() : _dbAt(point.direction);
    if (!_vertical) _setDb(_dragValue);
  }

  void _drag(DragUpdateDetails details) {
    final point = _offset(details.localPosition);
    if (!_vertical && point.distance < 9) return;
    final turn = (point.direction - _previousAngle + math.pi) % _turn - math.pi;
    final delta = _vertical
        ? -details.delta.dy / 4
        : turn / _arc * (_max - _min);
    _previousAngle = point.direction;
    _dragValue = (_dragValue + delta).clamp(_min.toDouble(), _max.toDouble());
    _setDb(_dragValue);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent || !widget.enabled) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowDown) {
      _setDb(_db - 1);
    } else if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp) {
      _setDb(_db + 1);
    } else if (key == LogicalKeyboardKey.home ||
        key == LogicalKeyboardKey.end) {
      _setDb(key == LogicalKeyboardKey.home ? _min : _max);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = widget.enabled;
    final minStep = enabled && _db > _min;
    final maxStep = enabled && _db < _max;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _size,
          child: Column(
            children: [
              Focus(
                focusNode: _focus,
                canRequestFocus: enabled,
                onFocusChange: (value) => setState(() => _focused = value),
                onKeyEvent: _onKey,
                child: Semantics(
                  slider: true,
                  enabled: enabled,
                  label: '음량 조절',
                  value: '$_dbLabel dB',
                  decreasedValue: minStep ? '${_label(_db - 1)} dB' : null,
                  increasedValue: maxStep ? '${_label(_db + 1)} dB' : null,
                  onDecrease: minStep ? () => _setDb(_db - 1) : null,
                  onIncrease: maxStep ? () => _setDb(_db + 1) : null,
                  child: MouseRegion(
                    cursor: enabled
                        ? SystemMouseCursors.grab
                        : SystemMouseCursors.basic,
                    child: GestureDetector(
                      excludeFromSemantics: true,
                      behavior: HitTestBehavior.opaque,
                      dragStartBehavior: DragStartBehavior.down,
                      onTapUp: enabled
                          ? (details) {
                              _focus.requestFocus();
                              final point = _offset(details.localPosition);
                              if (point.distance >= _size * .29) {
                                _setDb(_dbAt(point.direction));
                              }
                            }
                          : null,
                      onPanStart: enabled ? _startDrag : null,
                      onPanUpdate: enabled ? _drag : null,
                      child: CustomPaint(
                        painter: _GainDialPainter(
                          fraction: (_db - _min) / (_max - _min),
                          colors: colors,
                          focused: _focused,
                        ),
                        child: SizedBox.square(
                          dimension: _size,
                          child: Center(
                            child: ExcludeSemantics(
                              child: SizedBox(
                                width: 58,
                                height: 48,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        _dbLabel,
                                        style: theme.textTheme.headlineSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                              height: 1,
                                            ),
                                      ),
                                      Text(
                                        'dB',
                                        style: theme.textTheme.labelSmall,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('−12', style: theme.textTheme.labelSmall),
                    Text('+20', style: theme.textTheme.labelSmall),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FilledButton.tonalIcon(
                onPressed: enabled ? _auto : null,
                icon: _pending == null
                    ? const ImageIcon(
                        AssetImage('assets/icon/auto_gain.png'),
                        size: 18,
                      )
                    : const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                label: Text(_pending == null ? '자동' : '취소'),
              ),
              const SizedBox(height: 7),
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colors.outlineVariant),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [colors.surface, colors.surfaceContainerHighest],
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '1 dB 낮추기',
                      onPressed: minStep ? () => _setDb(_db - 1) : null,
                      icon: const Icon(Icons.remove, size: 18),
                    ),
                    Container(
                      width: 1,
                      height: 24,
                      color: colors.outlineVariant,
                    ),
                    IconButton(
                      tooltip: '1 dB 높이기',
                      onPressed: maxStep ? () => _setDb(_db + 1) : null,
                      icon: const Icon(Icons.add, size: 18),
                    ),
                  ],
                ),
              ),
              if (_status != null)
                Padding(
                  padding: const EdgeInsets.only(top: 5),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _status!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _error ? colors.error : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _GainDialPainter extends CustomPainter {
  const _GainDialPainter({
    required this.fraction,
    required this.colors,
    required this.focused,
  });

  final double fraction;
  final ColorScheme colors;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    const start = _GainSelectorState._start;
    const sweep = _GainSelectorState._arc;
    final angle = start + sweep * fraction;
    final track = Rect.fromCircle(center: center, radius: radius - 3);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4;
    canvas.drawArc(
      track,
      start,
      sweep,
      false,
      stroke..color = colors.outlineVariant,
    );
    canvas.drawArc(
      track,
      start,
      sweep * fraction,
      false,
      stroke..color = colors.primary,
    );
    final tick = Paint()
      ..color = colors.onSurfaceVariant.withValues(alpha: .44)
      ..strokeWidth = 1;
    for (var i = 0; i <= 32; i++) {
      final a = start + sweep * i / 32;
      final direction = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        center + direction * (radius - (i % 4 == 0 ? 14 : 12)),
        center + direction * (radius - 8),
        tick,
      );
    }
    final capRadius = radius - 17;
    final cap = Rect.fromCircle(center: center, radius: capRadius);
    canvas.drawShadow(
      Path()..addOval(cap),
      colors.shadow.withValues(alpha: .32),
      4,
      true,
    );
    canvas.drawCircle(
      center,
      capRadius,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surface, colors.surfaceContainerHighest],
        ).createShader(cap),
    );
    canvas.drawCircle(
      center,
      capRadius,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = colors.outlineVariant,
    );
    final pointer = Offset(math.cos(angle), math.sin(angle));
    canvas.drawLine(
      center + pointer * (capRadius - 5),
      center + pointer * (capRadius - 11),
      Paint()
        ..color = colors.primary
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
    if (focused) {
      canvas.drawCircle(
        center,
        radius - 1,
        Paint()
          ..style = PaintingStyle.stroke
          ..color = colors.primary
          ..strokeWidth = 1.5,
      );
    }
  }

  @override
  bool shouldRepaint(_GainDialPainter oldDelegate) =>
      fraction != oldDelegate.fraction ||
      colors != oldDelegate.colors ||
      focused != oldDelegate.focused;
}
