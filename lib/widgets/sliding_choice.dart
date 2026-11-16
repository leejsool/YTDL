import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 둥근 트랙 안에서 선택 표시가 좌우로 움직이는 단일 선택 버튼.
class SlidingChoice<T> extends StatelessWidget {
  const SlidingChoice({
    super.key,
    required this.values,
    required this.value,
    required this.labelBuilder,
    required this.onChanged,
    this.iconBuilder,
    this.detailBuilder,
  });

  final List<T> values;
  final T value;
  final String Function(T) labelBuilder;
  final IconData? Function(T)? iconBuilder;
  final String Function(T)? detailBuilder;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final canSelect = onChanged != null;
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    final selectedIndex = values.indexOf(value);
    final labelStyle = theme.textTheme.labelLarge!.copyWith(
      fontWeight: FontWeight.w700,
    );
    final labels = values.map(labelBuilder).toList(growable: false);
    final icons = values
        .map((option) => iconBuilder?.call(option))
        .toList(growable: false);
    const railPadding = 4.0;
    const segmentPadding = 2.0;
    const iconSize = 17.0;
    const iconGap = 6.0;
    const pill = StadiumBorder();

    Color tint(Color base, double alpha) =>
        Color.alphaBlend(colors.primary.withValues(alpha: alpha), base);

    Widget segment(int index) {
      final selected = index == selectedIndex;
      final icon = icons[index];
      final foreground = !canSelect
          ? colors.onSurface.withValues(alpha: .38)
          : selected
          ? colors.primary
          : colors.onSurfaceVariant;

      return Expanded(
        child: Semantics(
          checked: selected,
          inMutuallyExclusiveGroup: true,
          enabled: canSelect,
          child: InkWell(
            customBorder: pill,
            onTap: canSelect
                ? () {
                    if (!selected) onChanged!(values[index]);
                  }
                : null,
            focusColor: colors.primary.withValues(alpha: .20),
            hoverColor: colors.primary.withValues(alpha: .08),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 44),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: segmentPadding,
                  vertical: 6,
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: duration,
                      style: labelStyle.copyWith(color: foreground),
                      textAlign: TextAlign.center,
                      child: icon == null
                          ? Text(labels[index], softWrap: false)
                          : Builder(
                              builder: (context) => Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    icon,
                                    size: iconSize,
                                    color: DefaultTextStyle.of(context)
                                        .style
                                        .color,
                                  ),
                                  const SizedBox(width: iconGap),
                                  Text(labels[index], softWrap: false),
                                ],
                              ),
                            ),
                    ),
                    if (detailBuilder case final details?)
                      Text(
                        details(values[index]),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: canSelect
                              ? colors.onSurfaceVariant
                              : foreground,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final track = DecoratedBox(
      decoration: ShapeDecoration(
        shape: pill,
        color: tint(colors.surfaceContainerHighest, dark ? .13 : .10),
      ),
      child: Padding(
        padding: const EdgeInsets.all(railPadding),
        child: Stack(
          children: [
            if (selectedIndex >= 0)
              Positioned.fill(
                child: AnimatedAlign(
                  alignment: AlignmentDirectional(
                    values.length == 1
                        ? 0
                        : 2 * selectedIndex / (values.length - 1) - 1,
                    0,
                  ),
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  child: FractionallySizedBox(
                    widthFactor: 1 / values.length,
                    heightFactor: 1,
                    child: DecoratedBox(
                      decoration: ShapeDecoration(
                        color: tint(colors.surface, dark ? .24 : .025),
                        shape: StadiumBorder(
                          side: BorderSide(
                            color: colors.primary.withValues(alpha: .14),
                          ),
                        ),
                        shadows: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: dark ? .30 : .12,
                            ),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            Material(
              type: MaterialType.transparency,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var index = 0; index < values.length; index++)
                      segment(index),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 화면이 좁거나 글자가 커도 선택지를 한 줄에서 읽고 누를 수 있다.
        final textMeasure = TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          maxLines: 1,
        );
        var segmentWidth = 48.0;
        for (var index = 0; index < labels.length; index++) {
          textMeasure.text = TextSpan(text: labels[index], style: labelStyle);
          textMeasure.layout();
          final iconWidth = icons[index] == null ? 0 : iconSize + iconGap;
          segmentWidth = math.max(
            segmentWidth,
            (textMeasure.width + iconWidth + segmentPadding * 2).ceilToDouble(),
          );
        }
        textMeasure.dispose();

        final minWidth = segmentWidth * values.length + railPadding * 2;
        if (minWidth <= constraints.maxWidth) return track;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(width: minWidth, child: track),
        );
      },
    );
  }
}
