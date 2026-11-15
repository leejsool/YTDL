import 'package:flutter/material.dart';

/// 앱 전체에서 쓰는 둥근 알약 모양 버튼. 음량 조절의 − / + 버튼과 같은 모양(연한 테두리 + 은은한 그라데이션)이다.
/// [label] 이 없으면 아이콘만 있는 버튼이 된다. 여러 개를 이어 붙이려면 [PillGroup] 을 쓴다.
class PillButton extends StatelessWidget {
  const PillButton({
    super.key,
    required this.onPressed,
    required this.icon,
    this.label,
    this.tooltip,
    this.selected = false,
  });

  final VoidCallback? onPressed;
  final Widget icon;
  final Widget? label;
  final String? tooltip;

  /// 지금 켜져 있는 상태(예: 재생 중)를 강조한다.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final fg = enabled
        ? (selected ? colors.primary : colors.onSurface)
        : colors.onSurface.withValues(alpha: .38);
    final radius = BorderRadius.circular(24);
    Widget button = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        border: Border.all(
          color: selected ? colors.primary : colors.outlineVariant,
        ),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: selected
              ? [colors.secondaryContainer, colors.secondaryContainer]
              : [colors.surface, colors.surfaceContainerHighest],
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: radius,
        child: InkWell(
          onTap: onPressed,
          borderRadius: radius,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40, minWidth: 40),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: label == null ? 10 : 14,
              ),
              child: IconTheme(
                data: IconThemeData(color: fg, size: 18),
                child: DefaultTextStyle.merge(
                  style: Theme.of(context).textTheme.labelLarge!
                      .copyWith(color: fg),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      icon,
                      if (label != null) ...[
                        const SizedBox(width: 7),
                        Flexible(child: label!),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (tooltip != null) button = Tooltip(message: tooltip!, child: button);
    return Semantics(button: true, enabled: enabled, child: button);
  }
}

/// 여러 아이콘 버튼을 하나의 알약으로 묶는다(− | + 처럼 사이에 가는 선).
class PillGroup extends StatelessWidget {
  const PillGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return DecoratedBox(
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
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0)
              Container(width: 1, height: 24, color: colors.outlineVariant),
            children[i],
          ],
        ],
      ),
    );
  }
}
