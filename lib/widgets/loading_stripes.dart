import 'package:flutter/material.dart';

/// 로딩 중인 그림 자리에 깔아 두는 검은색 · 회색 사선 무늬(천천히 흐른다).
class LoadingStripes extends StatefulWidget {
  const LoadingStripes({super.key});

  @override
  State<LoadingStripes> createState() => _LoadingStripesState();
}

class _LoadingStripesState extends State<LoadingStripes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        painter: _StripesPainter(_c),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _StripesPainter extends CustomPainter {
  _StripesPainter(this.t) : super(repaint: t);

  final Animation<double> t;

  static const _dark = Color(0xFF202024);
  static const _gray = Color(0xFF6A6A72);
  static const _band = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = _dark);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    final paint = Paint()..color = _gray;
    // 사선(\ 방향) 띠: 한 주기(= 두 띠 폭)만큼 옮기면 같은 모양이라 끊김 없이 흐른다.
    final period = _band * 2;
    final shift = t.value * period;
    final reach = size.width + size.height;
    for (var x = -reach; x < reach + period; x += period) {
      final left = x + shift;
      final path = Path()
        ..moveTo(left, 0)
        ..lineTo(left + _band, 0)
        ..lineTo(left + _band + size.height, size.height)
        ..lineTo(left + size.height, size.height)
        ..close();
      canvas.drawPath(path, paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_StripesPainter old) => false;
}
