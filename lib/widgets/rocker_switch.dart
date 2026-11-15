import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 로커 스위치의 한쪽 선택지.
class RockerOption<T> {
  const RockerOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// 진짜 시소(로커) 스위치처럼 생긴 2지선다 버튼.
/// 오목하게 파인 회색 홈 안에서 두툼한 흰 스위치 면(옆면 두께와 그림자가 있음)이 좌우로 딸깍 넘어가고,
/// 면은 눌린 쪽으로 살짝 기울어진다. 선택된 쪽 글자는 스위치 면 위에서 보라색으로 보인다.
class RockerSwitch<T> extends StatelessWidget {
  const RockerSwitch({
    super.key,
    required this.left,
    required this.right,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.width = 250,
  });

  final RockerOption<T> left;
  final RockerOption<T> right;
  final T value;
  final ValueChanged<T>? onChanged;
  final bool enabled;
  final double width;

  static const _height = 60.0;
  static const _inset = 5.0;

  void _select(RockerOption<T> o) {
    if (!enabled || onChanged == null || o.value == value) return;
    // 딸깍하는 손맛: 폰에서는 짧은 진동과 터치음.
    HapticFeedback.selectionClick();
    if (Platform.isAndroid) SystemSound.play(SystemSoundType.click);
    onChanged!(o.value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final canTap = enabled && onChanged != null;
    final onLeft = value == left.value;

    final edge = dark ? const Color(0xFF5E5470) : const Color(0xFF7D7589);
    final wellTop = dark ? const Color(0xFF0F0C14) : const Color(0xFFB9B2C6);
    final wellBottom = dark ? const Color(0xFF2A2335) : const Color(0xFFE4E0EC);
    final faceTop = dark ? const Color(0xFF4A4060) : Colors.white;
    final faceBottom = dark ? const Color(0xFF362E48) : const Color(0xFFEDEAF3);
    final wall = dark ? const Color(0xFF1C1626) : const Color(0xFF9D96AA);
    final dim = colors.onSurface.withValues(alpha: .38);
    final idle = canTap ? colors.onSurfaceVariant : dim;
    final active = canTap ? colors.primary : dim;

    final paddleW = (width - _inset * 2) / 2;
    final paddleH = _height - _inset * 2 - 4; // 아래쪽 4px 은 옆면 두께

    Widget label(RockerOption<T> o, Color color, {bool bold = false}) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (o.icon != null) ...[
            Icon(o.icon, size: 18, color: color),
            const SizedBox(width: 6),
          ],
          Text(
            o.label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: color,
              fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ],
      );
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Semantics(
        container: true,
        label: '${left.label} 또는 ${right.label}',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) =>
              _select(d.localPosition.dx < width / 2 ? left : right),
          child: SizedBox(
            width: width,
            height: _height,
            child: TweenAnimationBuilder<double>(
              // 1 = 왼쪽이 올라옴, -1 = 오른쪽이 올라옴. 살짝 튕기며 넘어간다.
              tween: Tween(end: onLeft ? 1.0 : -1.0),
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutBack,
              builder: (context, t, _) {
                final p = (1 - t) / 2; // 0 = 왼쪽 끝, 1 = 오른쪽 끝
                final dx = _inset + p * (width - _inset * 2 - paddleW);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // 오목한 홈
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          border: Border.all(color: edge, width: 1.4),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [wellTop, wellBottom],
                          ),
                        ),
                      ),
                    ),
                    // 홈 바닥에 놓인 두 글자(선택 안 된 쪽이 보인다)
                    Positioned.fill(
                      child: Row(
                        children: [
                          Expanded(child: Center(child: label(left, idle))),
                          Expanded(child: Center(child: label(right, idle))),
                        ],
                      ),
                    ),
                    // 스위치 면: 옆면(두께) → 몸통 → 글자, 눌린 쪽으로 기울어짐
                    Positioned(
                      left: dx,
                      top: _inset,
                      width: paddleW,
                      height: paddleH + 4,
                      child: Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()
                          ..setEntry(3, 2, 0.0016)
                          ..rotateY(t * 0.16),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // 옆면(두께) + 그림자
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 4,
                              height: paddleH,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: wall,
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: dark ? .6 : .38,
                                      ),
                                      blurRadius: 6,
                                      offset: Offset(-t * 3, 4),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // 윗면
                            Positioned(
                              left: 0,
                              right: 0,
                              top: 0,
                              height: paddleH,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: edge.withValues(alpha: .7),
                                    width: 1,
                                  ),
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [faceTop, faceBottom],
                                  ),
                                ),
                                child: Center(
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 140),
                                    child: KeyedSubtree(
                                      key: ValueKey(onLeft),
                                      child: label(
                                        onLeft ? left : right,
                                        active,
                                        bold: true,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
