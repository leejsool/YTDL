import 'package:flutter/material.dart';

import '../util/time_format.dart';

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
    final max = widget.duration.toDouble();
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
        CutRangeSlider(
          max: max,
          values: RangeValues(widget.start.toDouble(), widget.end.toDouble()),
          format: (t) => formatSeconds(t.round()),
          onChanged: widget.enabled
              ? (v) {
                  var s = v.start.round();
                  var e = v.end.round();
                  if (e - s < 1) {
                    if (s != widget.start) {
                      s = e - 1;
                    } else {
                      e = s + 1;
                    }
                  }
                  widget.onChanged(s, e);
                }
              : null,
        ),
        const SizedBox(height: 6),
        Text(
          '잘라낼 길이 ${formatSeconds(length)}  (전체 ${formatSeconds(widget.duration)})',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// 두 손잡이 사이의 자를 구간과 시간 눈금을 함께 표시한다.
class CutRangeSlider extends StatelessWidget {
  const CutRangeSlider({
    super.key,
    required this.max,
    required this.values,
    required this.format,
    required this.onChanged,
  });

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
            max: max,
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
              for (final value in [0.0, max / 2, max])
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
