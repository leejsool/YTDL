import 'package:flutter/material.dart';

import '../models.dart';

/// 음량 조절 선택: 그대로 / 직접(슬라이더) / 자동.
/// 다운로드 화면(음원)과 편집 화면이 함께 쓴다.
class GainSelector extends StatefulWidget {
  const GainSelector({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
  });

  final AudioGain value;
  final ValueChanged<AudioGain> onChanged;
  final bool enabled;

  static const minDb = -12.0;
  static const maxDb = 20.0;

  @override
  State<GainSelector> createState() => _GainSelectorState();
}

class _GainSelectorState extends State<GainSelector> {
  /// "직접"으로 돌아왔을 때 쓸 마지막 값. 처음엔 +6dB(소리가 작은 음원에 무난한 정도).
  double _manualDb = 6;

  @override
  void initState() {
    super.initState();
    if (widget.value.mode == GainMode.manual && widget.value.db != 0) {
      _manualDb = widget.value.db;
    }
  }

  void _pick(GainMode m) {
    widget.onChanged(switch (m) {
      GainMode.none => const AudioGain.none(),
      GainMode.manual => AudioGain.manual(_manualDb),
      GainMode.auto => const AudioGain.auto(),
    });
  }

  String _fmt(double db) => '${db > 0 ? '+' : ''}${db.toStringAsFixed(0)} dB';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mode = widget.value.mode;
    final on = widget.enabled;

    Widget chip(GainMode m, String label) => ChoiceChip(
          label: Text(label),
          selected: mode == m,
          onSelected: on ? (_) => _pick(m) : null,
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text('음량', style: theme.textTheme.labelLarge),
            chip(GainMode.none, '그대로'),
            chip(GainMode.manual, '직접 조절'),
            chip(GainMode.auto, '자동으로 키우기'),
          ],
        ),
        if (mode == GainMode.manual)
          Row(children: [
            Expanded(
              child: Slider(
                min: GainSelector.minDb,
                max: GainSelector.maxDb,
                divisions: (GainSelector.maxDb - GainSelector.minDb).round(),
                value: _manualDb.clamp(GainSelector.minDb, GainSelector.maxDb),
                label: _fmt(_manualDb),
                onChanged: on
                    ? (v) {
                        setState(() => _manualDb = v);
                        widget.onChanged(AudioGain.manual(v));
                      }
                    : null,
              ),
            ),
            SizedBox(
              width: 64,
              child: Text(_fmt(_manualDb), textAlign: TextAlign.end, style: theme.textTheme.titleSmall),
            ),
          ]),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            switch (mode) {
              GainMode.none => '소리가 너무 작으면 키워 보세요.',
              GainMode.manual => '+6 dB 는 약 2배, +12 dB 는 약 4배 크기예요. 찌그러지지 않게 최대치는 자동으로 막아 줘요.',
              GainMode.auto => '유튜브 표준 음량(-14 LUFS)에 맞춰 알아서 키우거나 줄여요.',
            },
            style: theme.textTheme.bodySmall,
          ),
        ),
        if (widget.value.isActive)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '음량을 바꾸면 소리를 다시 인코딩해서 저장해요(시간이 조금 더 걸리고, 음질이 아주 약간 달라질 수 있어요).',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
