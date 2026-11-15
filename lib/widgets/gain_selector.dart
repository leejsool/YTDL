import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import 'pill_button.dart';

class GainSelector extends StatefulWidget {
  const GainSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.onAuto,
    required this.analysisSource,
    this.onPreview,
    this.busy = false,
    this.enabled = true,
  });

  /// 지금 고른 음량이 적용된 짧은 샘플 파일을 만들어 경로를 돌려준다. null 이면 '들어보기' 버튼을 숨긴다.
  final Future<String> Function()? onPreview;

  /// 바깥에서 음량을 적용하는 중일 때 true. 노브 테두리에 빛나는 띠가 돈다.
  final bool busy;

  final AudioGain value;
  final ValueChanged<AudioGain> onChanged;
  final Future<double> Function(CancelToken token) onAuto;
  final Object analysisSource;
  final bool enabled;

  static const minDb = -30;
  static const maxDb = 20;

  @override
  State<GainSelector> createState() => _GainSelectorState();
}

class _GainSelectorState extends State<GainSelector>
    with SingleTickerProviderStateMixin {
  // 로딩 중 노브 테두리를 도는 빛 띠.
  late final AnimationController _spin = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );
  bool get _working => widget.busy || _pending != null || _previewLoading;
  void _syncSpin() {
    if (_working) {
      if (!_spin.isAnimating) _spin.repeat();
    } else if (_spin.isAnimating) {
      _spin.stop();
    }
  }

  static const _size = 112.0;
  static const _arc = math.pi * 1.5;
  static const _start = math.pi * .75;
  static const _turn = math.pi * 2;
  static const _min = GainSelector.minDb;
  static const _max = GainSelector.maxDb;

  final _focus = FocusNode();
  CancelToken? _pending;
  AudioPlayer? _player;
  bool _previewLoading = false;
  bool _previewPlaying = false;
  String? _previewError;
  String? _status;
  bool _error = false;
  bool _focused = false;
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
    _spin.dispose();
    _player?.dispose();
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

  Future<void> _stopPreview() async {
    if (_player == null) return;
    await _player!.stop();
    if (mounted) setState(() => _previewPlaying = false);
  }

  Future<void> _preview() async {
    final make = widget.onPreview;
    if (make == null) return;
    if (_previewPlaying) {
      await _stopPreview();
      return;
    }
    setState(() {
      _previewLoading = true;
      _previewError = null;
    });
    try {
      final path = await make();
      if (!mounted) return;
      final p = _player ??= AudioPlayer()
        ..onPlayerComplete.listen((_) {
          if (mounted) setState(() => _previewPlaying = false);
        });
      await p.setReleaseMode(ReleaseMode.stop);
      await p.stop();
      await p.play(DeviceFileSource(path));
      if (mounted) setState(() => _previewPlaying = true);
    } catch (e) {
      if (mounted) {
        setState(
          () => _previewError =
              '소리를 만들지 못했어요: ${e.toString().replaceFirst('Exception: ', '')}',
        );
      }
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  void _setDb(num value) {
    final next = value.round().clamp(_min, _max);
    if (next != _db && _previewPlaying) unawaited(_stopPreview());
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

  // 노브 둘레에 여유 터치 영역을 둔다(손가락이 조금 벗어나도 노브가 잡히게).
  static const _pad = 14.0;

  Offset _offset(Offset position) =>
      position - const Offset(_size / 2 + _pad, _size / 2 + _pad);

  double _dbAt(double angle) {
    var distance = (angle - _start) % _turn;
    if (distance > _arc) {
      distance = distance - _arc < _turn - distance ? _arc : 0;
    }
    return _min + distance / _arc * (_max - _min);
  }

  void _startDrag(DragStartDetails details) {
    _focus.requestFocus();
    // 진짜 볼륨 노브처럼: 어디를 잡든 값이 튀지 않고, 잡은 채 시계방향으로 돌리면 커지고
    // 반시계방향으로 돌리면 작아진다(손가락이 움직인 각도만큼).
    final point = _offset(details.localPosition);
    _previousAngle = point.direction;
    _dragValue = _db.toDouble();
  }

  void _drag(DragUpdateDetails details) {
    final point = _offset(details.localPosition);
    if (point.distance < 9) return;
    final turn = (point.direction - _previousAngle + math.pi) % _turn - math.pi;
    final delta = turn / _arc * (_max - _min);
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
    _syncSpin();
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final enabled = widget.enabled;
    final minStep = enabled && _db > _min;
    final maxStep = enabled && _db < _max;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: _size + _pad * 2,
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
                    // 스크롤 화면 안에서도 노브를 잡는 즉시 드래그가 노브로 오도록(화면이 같이 스크롤되지 않게)
                    // 바로 제스처를 가져가는 인식기를 쓴다.
                    child: RawGestureDetector(
                      excludeFromSemantics: true,
                      behavior: HitTestBehavior.opaque,
                      gestures: {
                        _EagerPanRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              _EagerPanRecognizer
                            >(_EagerPanRecognizer.new, (r) {
                              r
                                ..dragStartBehavior = DragStartBehavior.down
                                ..onStart = enabled ? _startDrag : null
                                ..onUpdate = enabled ? _drag : null;
                            }),
                        TapGestureRecognizer:
                            GestureRecognizerFactoryWithHandlers<
                              TapGestureRecognizer
                            >(TapGestureRecognizer.new, (r) {
                              r.onTapUp = enabled
                                  ? (details) {
                                      _focus.requestFocus();
                                      final point = _offset(
                                        details.localPosition,
                                      );
                                      if (point.distance >= _size * .29) {
                                        _setDb(_dbAt(point.direction));
                                      }
                                    }
                                  : null;
                            }),
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(_pad),
                        child: CustomPaint(
                          painter: _GainDialPainter(
                            spin: _spin,
                            working: _working,
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
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: _pad + 3),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('−30', style: theme.textTheme.labelSmall),
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
              PillButton(
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
                label: Text(_pending == null ? '자동' : '취소'),
              ),
              const SizedBox(height: 7),
              PillGroup(
                children: [
                  IconButton(
                    tooltip: '1 dB 낮추기',
                    onPressed: minStep ? () => _setDb(_db - 1) : null,
                    icon: const Icon(Icons.remove, size: 18),
                  ),
                  IconButton(
                    tooltip: '1 dB 높이기',
                    onPressed: maxStep ? () => _setDb(_db + 1) : null,
                    icon: const Icon(Icons.add, size: 18),
                  ),
                ],
              ),
              if (widget.onPreview != null) ...[
                const SizedBox(height: 7),
                PillButton(
                  onPressed: enabled && !_previewLoading ? _preview : null,
                  icon: _previewLoading
                      ? const SizedBox.square(
                          dimension: 15,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _previewPlaying ? Icons.stop : Icons.play_arrow,
                          size: 18,
                        ),
                  label: Text(
                    _previewLoading
                        ? '준비 중…'
                        : _previewPlaying
                        ? '멈추기'
                        : '들어보기',
                  ),
                ),
                if (_previewError != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 5),
                    child: Text(
                      _previewError!,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colors.error,
                      ),
                    ),
                  ),
              ],
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

/// 손가락을 대자마자 제스처 경쟁에서 이기는 드래그 인식기.
class _EagerPanRecognizer extends PanGestureRecognizer {
  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    resolve(GestureDisposition.accepted);
  }
}

class _GainDialPainter extends CustomPainter {
  const _GainDialPainter({
    required this.fraction,
    required this.colors,
    required this.focused,
    required this.spin,
    required this.working,
  }) : super(repaint: spin);

  final Animation<double> spin;
  final bool working;
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
    if (working) {
      // 테두리를 도는 빛 띠: 꼬리가 흐려지는 회전 그라데이션 + 번지는 빛.
      final rim = Rect.fromCircle(center: center, radius: radius - 1.5);
      final turn = spin.value * math.pi * 2;
      final shader = SweepGradient(
        colors: [
          colors.primary.withValues(alpha: 0),
          colors.primary.withValues(alpha: .15),
          colors.primary,
          Colors.white,
        ],
        stops: const [0, .45, .92, 1],
        transform: GradientRotation(turn),
      ).createShader(rim);
      canvas.drawArc(
        rim,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5)
          ..shader = shader,
      );
      canvas.drawArc(
        rim,
        0,
        math.pi * 2,
        false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5
          ..strokeCap = StrokeCap.round
          ..shader = shader,
      );
    }
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
      working != oldDelegate.working ||
      fraction != oldDelegate.fraction ||
      colors != oldDelegate.colors ||
      focused != oldDelegate.focused;
}
