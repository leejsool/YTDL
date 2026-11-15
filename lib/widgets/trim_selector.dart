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
        RangeSlider(
          min: 0,
          max: max,
          divisions: widget.duration > 0 ? widget.duration : null,
          values: RangeValues(widget.start.toDouble(), widget.end.toDouble()),
          labels: RangeLabels(formatSeconds(widget.start), formatSeconds(widget.end)),
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
        Row(
          children: [
            _timeField('시작', _startCtl),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Text('~'),
            ),
            _timeField('끝', _endCtl),
          ],
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
