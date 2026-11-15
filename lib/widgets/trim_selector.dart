import 'dart:async';

import 'package:flutter/material.dart';

import '../util/time_format.dart';
import 'pill_button.dart';

/// 구간 선택: 슬라이더 + 시작/끝 시간 직접 입력(m:ss, h:mm:ss).
class TrimSelector extends StatefulWidget {
  const TrimSelector({
    super.key,
    required this.duration,
    required this.start,
    required this.end,
    required this.onChanged,
    this.enabled = true,
  });

  final int duration;
  final int start;
  final int end;
  final bool enabled;
  final void Function(int start, int end) onChanged;

  @override
  State<TrimSelector> createState() => _TrimSelectorState();
}

class _TrimSelectorState extends State<TrimSelector> {
  late final TextEditingController _startCtl;
  late final TextEditingController _endCtl;

  @override
  void initState() {
    super.initState();
    _startCtl = TextEditingController(text: formatSeconds(widget.start));
    _endCtl = TextEditingController(text: formatSeconds(widget.end));
  }

  @override
  void didUpdateWidget(TrimSelector old) {
    super.didUpdateWidget(old);
    // 입력 중인 값과 다를 때만 텍스트를 갱신해서 커서가 튀지 않게 한다.
    if (parseSeconds(_startCtl.text) != widget.start) {
      _startCtl.text = formatSeconds(widget.start);
    }
    if (parseSeconds(_endCtl.text) != widget.end) {
      _endCtl.text = formatSeconds(widget.end);
    }
  }

  @override
  void dispose() {
    _startCtl.dispose();
    _endCtl.dispose();
    super.dispose();
  }

  void _commitText() {
    var s = parseSeconds(_startCtl.text) ?? widget.start;
    var e = parseSeconds(_endCtl.text) ?? widget.end;
    s = s.clamp(0, widget.duration - 1);
    e = e.clamp(s + 1, widget.duration);
    _startCtl.text = formatSeconds(s);
    _endCtl.text = formatSeconds(e);
    widget.onChanged(s, e);
  }

  Widget _timeField(String label, TextEditingController c) {
    return Expanded(
      child: TextField(
        controller: c,
        enabled: widget.enabled,
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

  @override
  Widget build(BuildContext context) {
    final length = widget.end - widget.start;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _timeField('시작', _startCtl),
            const SizedBox(width: 12),
            _timeField('끝', _endCtl),
          ],
        ),
        ZoomRangeSlider(
          total: widget.duration.toDouble(),
          start: widget.start.toDouble(),
          end: widget.end.toDouble(),
          enabled: widget.enabled,
          minViewSpan: 10,
          minSelection: 1,
          format: (t) => formatSeconds(t.round()),
          caption:
              '잘라낼 길이 ${formatSeconds(length)}  (전체 ${formatSeconds(widget.duration)})',
          onChanged: (s, e) => widget.onChanged(
            s.round().clamp(0, widget.duration - 1),
            e.round().clamp(1, widget.duration),
          ),
        ),
      ],
    );
  }
}

/// 두 손잡이 슬라이더 + 확대/축소 + 확대했을 때 나오는 스크롤 막대. 단위는 호출하는 쪽이 정한다
/// (영상 편집은 초, 음원 편집은 밀리초). 시작/끝이 바뀌면 [onChanged] 로 알린다.
class ZoomRangeSlider extends StatefulWidget {
  const ZoomRangeSlider({
    super.key,
    required this.total,
    required this.start,
    required this.end,
    required this.format,
    required this.onChanged,
    required this.caption,
    required this.minViewSpan,
    required this.minSelection,
    this.enabled = true,
  });

  final double total;
  final double start;
  final double end;
  final bool enabled;

  /// 확대했을 때 더 이상 좁힐 수 없는 보이는 길이.
  final double minViewSpan;

  /// 선택 구간의 최소 길이.
  final double minSelection;
  final String Function(double) format;

  /// 슬라이더 아래 왼쪽에 보여 줄 글(확대 중이면 보이는 범위가 뒤에 붙는다).
  final String caption;
  final void Function(double start, double end) onChanged;

  @override
  State<ZoomRangeSlider> createState() => _ZoomRangeSliderState();
}

class _ZoomRangeSliderState extends State<ZoomRangeSlider>
    with SingleTickerProviderStateMixin {
  double _viewStart = 0;
  late double _viewEnd = widget.total;
  (double, double)? _dragFrom;

  double get _minViewSpan => widget.minViewSpan;
  double get _span => _viewEnd - _viewStart;
  bool get _zoomed => _span < widget.total - 0.5;

  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  VoidCallback? _tick;
  Timer? _delay; // 움직이기 시작하기 전 0.2초 기다림

  @override
  void didUpdateWidget(ZoomRangeSlider old) {
    super.didUpdateWidget(old);
    if (old.total != widget.total) {
      _viewStart = 0;
      _viewEnd = widget.total;
    }
  }

  @override
  void dispose() {
    _delay?.cancel();
    _anim.dispose();
    super.dispose();
  }

  /// 보이는 구간을 [start]~[end] 로 바꾼다. [animate] 면 부드럽게 늘었다 줄었다 하며 바뀐다.
  void _setView(double start, double end, {bool animate = false}) {
    final total = widget.total;
    final span = (end - start)
        .clamp(_minViewSpan < total ? _minViewSpan : total, total)
        .toDouble();
    final vs = start.clamp(0.0, total - span).toDouble();
    final fromS = _viewStart;
    final fromE = _viewEnd;
    final toS = vs;
    final toE = vs + span;
    _delay?.cancel();
    final old = _tick;
    if (old != null) _anim.removeListener(old);
    _tick = null;
    _anim.stop();
    if (!animate) {
      setState(() {
        _viewStart = toS;
        _viewEnd = toE;
      });
      return;
    }
    final curve = CurvedAnimation(parent: _anim, curve: Curves.easeInOutCubic);
    void tick() {
      if (!mounted) return;
      setState(() {
        _viewStart = fromS + (toS - fromS) * curve.value;
        _viewEnd = fromE + (toE - fromE) * curve.value;
      });
    }

    _tick = tick;
    // 눈이 따라갈 수 있게 0.2초 쉬었다가 천천히 움직인다.
    _delay = Timer(const Duration(milliseconds: 200), () {
      if (!mounted || _tick != tick) return;
      _anim
        ..addListener(tick)
        ..forward(from: 0);
    });
  }

  void _zoom(bool inward) {
    final focus = (widget.start + widget.end) / 2;
    final center = focus.clamp(_viewStart, _viewEnd).toDouble();
    final span = inward ? _span / 2 : _span * 2;
    _setView(center - span / 2, center + span / 2, animate: true);
  }

  /// 손잡이를 놓았을 때: 시작 손잡이면 그 앞 조금부터 끝까지, 끝 손잡이면 처음부터 그 뒤 조금까지로 확대한다.
  void _autoZoom(RangeValues v) {
    final from = _dragFrom;
    _dragFrom = null;
    if (from == null) return;
    final margin = _span * 0.1;
    var ns = _viewStart;
    var ne = _viewEnd;
    if (widget.start != from.$1) {
      ns = widget.start - margin;
    } else if (widget.end != from.$2) {
      ne = widget.end + margin;
    } else {
      return;
    }
    ns = ns.clamp(_viewStart, _viewEnd).toDouble();
    ne = ne.clamp(_viewStart, _viewEnd).toDouble();
    if ((ne - ns) <= _span * 0.85 && (ne - ns) >= _minViewSpan) {
      _setView(ns, ne, animate: true);
    }
  }

  void _onSlide(RangeValues v) {
    // 화면 밖으로 밀려난 손잡이는 건드리지 않고, 움직인 손잡이만 반영한다.
    final shownStart = widget.start.clamp(_viewStart, _viewEnd).toDouble();
    final shownEnd = widget.end.clamp(_viewStart, _viewEnd).toDouble();
    var s = v.start != shownStart ? v.start : widget.start;
    var e = v.end != shownEnd ? v.end : widget.end;
    final min = widget.minSelection;
    if (e - s < min) {
      if (s != widget.start) {
        s = e - min;
      } else {
        e = s + min;
      }
    }
    widget.onChanged(
      s.clamp(0.0, widget.total - min).toDouble(),
      e.clamp(min, widget.total).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CutRangeSlider(
          min: _viewStart,
          max: _viewEnd,
          values: RangeValues(
            widget.start.clamp(_viewStart, _viewEnd).toDouble(),
            widget.end.clamp(_viewStart, _viewEnd).toDouble(),
          ),
          format: widget.format,
          onChangeStart: widget.enabled
              ? (_) => _dragFrom = (widget.start, widget.end)
              : null,
          onChangeEnd: widget.enabled ? _autoZoom : null,
          onChanged: widget.enabled ? _onSlide : null,
        ),
        if (_zoomed)
          _ViewScroller(
            total: widget.total,
            start: _viewStart,
            end: _viewEnd,
            selStart: widget.start,
            selEnd: widget.end,
            enabled: widget.enabled,
            onMove: (vs) => _setView(vs, vs + _span),
          ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                widget.caption +
                    (_zoomed
                        ? '\n확대해서 보는 중 ${widget.format(_viewStart)}–${widget.format(_viewEnd)}'
                        : ''),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            PillGroup(
              children: [
                IconButton(
                  tooltip: '슬라이더 축소',
                  onPressed: widget.enabled && _zoomed
                      ? () => _zoom(false)
                      : null,
                  icon: const Icon(Icons.zoom_out, size: 20),
                ),
                IconButton(
                  tooltip: '슬라이더 확대',
                  onPressed: widget.enabled && _span / 2 >= _minViewSpan
                      ? () => _zoom(true)
                      : null,
                  icon: const Icon(Icons.zoom_in, size: 20),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// 두 손잡이 사이의 자를 구간과 시간 눈금을 함께 표시한다.
class CutRangeSlider extends StatelessWidget {
  const CutRangeSlider({
    super.key,
    this.min = 0,
    required this.max,
    required this.values,
    required this.format,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
  });

  final double min;
  final ValueChanged<RangeValues>? onChangeStart;
  final ValueChanged<RangeValues>? onChangeEnd;
  final double max;
  final RangeValues values;
  final String Function(double) format;
  final ValueChanged<RangeValues>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 7,
            activeTrackColor: colors.primary,
            inactiveTrackColor: colors.surfaceContainerHighest,
            rangeTrackShape: const RoundedRectRangeSliderTrackShape(),
            rangeThumbShape: _CutHandle(colors),
            showValueIndicator: ShowValueIndicator.onDrag,
          ),
          child: RangeSlider(
            min: min,
            max: max,
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
            values: values,
            labels: RangeLabels(format(values.start), format(values.end)),
            semanticFormatterCallback: format,
            onChanged: onChanged,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final value in [min, (min + max) / 2, max])
                Text(
                  format(value),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 확대해서 볼 때 아래에 나오는 가로 스크롤 막대. 끌어서 보이는 구간을 옮긴다.
class _ViewScroller extends StatelessWidget {
  const _ViewScroller({
    required this.total,
    required this.start,
    required this.end,
    required this.onMove,
    required this.selStart,
    required this.selEnd,
    this.enabled = true,
  });

  final double selStart;
  final double selEnd;
  final double total;
  final double start;
  final double end;
  final bool enabled;
  final ValueChanged<double> onMove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: LayoutBuilder(
        builder: (context, box) {
          final w = box.maxWidth;
          final span = end - start;
          final room = total - span;
          final thumbW = (w * span / total).clamp(24.0, w).toDouble();
          final left = room <= 0 ? 0.0 : (w - thumbW) * start / room;

          return Semantics(
            label: '확대 구간 이동',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) {
                if (!enabled || w <= thumbW) return;
                onMove(start + d.delta.dx / (w - thumbW) * room);
              },
              onTapDown: (d) {
                if (!enabled || w <= thumbW) return;
                final target = (d.localPosition.dx - thumbW / 2) / (w - thumbW);
                onMove(target.clamp(0.0, 1.0) * room);
              },
              child: SizedBox(
                height: 22,
                child: Stack(
                  alignment: Alignment.centerLeft,
                  children: [
                    Container(
                      height: 8,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    // 내가 고른 구간(전체 길이 기준)을 진한 색으로 표시한다.
                    Positioned(
                      left: w * (selStart / total).clamp(0.0, 1.0),
                      width: (w * ((selEnd - selStart) / total).clamp(0.0, 1.0))
                          .clamp(3.0, w)
                          .toDouble(),
                      child: Container(
                        height: 8,
                        decoration: BoxDecoration(
                          color: enabled ? colors.primary : colors.outline,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                    // 지금 위에 보이는 확대 구간(투명한 테두리 상자).
                    Positioned(
                      left: left,
                      width: thumbW,
                      child: Container(
                        height: 18,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .12),
                          border: Border.all(
                            color: enabled ? colors.primary : colors.outline,
                            width: 1.5,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _CutHandle extends RangeSliderThumbShape {
  const _CutHandle(this.colors);

  final ColorScheme colors;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(16, 24);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    bool isDiscrete = false,
    bool isEnabled = false,
    bool isOnTop = false,
    TextDirection textDirection = TextDirection.ltr,
    required SliderThemeData sliderTheme,
    Thumb thumb = Thumb.start,
    bool isPressed = false,
  }) {
    final rect = Rect.fromCenter(center: center, width: 15, height: 23);
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(5));
    final accent = isEnabled ? colors.primary : colors.outline;
    final canvas = context.canvas;
    canvas.drawShadow(
      Path()..addRRect(shape),
      colors.shadow.withValues(alpha: .27),
      2,
      true,
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.surface, colors.surfaceContainerHighest],
        ).createShader(rect),
    );
    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..color = accent,
    );
    final grip = Paint()
      ..color = accent.withValues(alpha: .7)
      ..strokeWidth = 1;
    for (final x in [-1.6, 1.6]) {
      canvas.drawLine(center + Offset(x, -4), center + Offset(x, 4), grip);
    }
  }
}

/// 영상 길이를 아직 모를 때 보여 주는 구간 선택기 뼈대(값은 ??, 흐리게 · 누를 수 없게 쓴다).
class TrimSelectorSkeleton extends StatelessWidget {
  const TrimSelectorSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    Widget field(String label) => Expanded(
      child: TextField(
        enabled: false,
        textAlign: TextAlign.center,
        decoration: InputDecoration(
          labelText: label,
          hintText: '??',
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [field('시작'), const SizedBox(width: 12), field('끝')]),
        CutRangeSlider(
          max: 1,
          values: const RangeValues(0, 1),
          format: (_) => '??',
          onChanged: null,
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(
              child: Text(
                '잘라낼 길이 ??  (전체 ??)',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const PillGroup(
              children: [
                IconButton(
                  onPressed: null,
                  icon: Icon(Icons.zoom_out, size: 20),
                ),
                IconButton(
                  onPressed: null,
                  icon: Icon(Icons.zoom_in, size: 20),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
