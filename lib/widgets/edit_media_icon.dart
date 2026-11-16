import 'package:flutter/material.dart';

import '../models.dart';

/// 음원 편집과 영상 메뉴에 쓰는 아이콘.
class EditMediaIcon extends StatelessWidget {
  const EditMediaIcon.audio({super.key, this.size}) : _kind = MediaKind.audio;
  const EditMediaIcon.video({super.key, this.size}) : _kind = MediaKind.video;

  final MediaKind _kind;
  final double? size;

  @override
  Widget build(BuildContext context) {
    final iconTheme = IconTheme.of(context);
    final color = iconTheme.color ?? Theme.of(context).colorScheme.onSurface;
    return CustomPaint(
      size: Size.square(size ?? iconTheme.size ?? 24),
      painter: _EditMediaPainter(
        _kind,
        color.withValues(alpha: color.a * (iconTheme.opacity ?? 1)),
      ),
    );
  }
}

class _EditMediaPainter extends CustomPainter {
  const _EditMediaPainter(this.kind, this.color);

  final MediaKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 24, size.height / 24);
    switch (kind) {
      case MediaKind.audio:
        _paintScissors(canvas);
      case MediaKind.video:
        _paintClapperboard(canvas);
    }
    canvas.restore();
  }

  static final Path _scissors = _makeScissors();
  static final Path _note = Path()
    ..moveTo(18.7, 6.2)
    ..cubicTo(20.1, 7.2, 22.8, 7.3, 23, 9.4)
    ..quadraticBezierTo(23.2, 10.4, 22.5, 11.4)
    ..quadraticBezierTo(22.3, 9.8, 20.6, 9.4)
    ..lineTo(20.6, 14.4)
    ..cubicTo(20.6, 16.1, 18.6, 17.2, 16.9, 16.8)
    ..cubicTo(15.1, 16.4, 15.2, 14.8, 16.3, 13.9)
    ..quadraticBezierTo(17.4, 13, 18.7, 13.2)
    ..close();

  static Path _makeScissors() {
    final blades = Path()
      ..moveTo(6.1, 7.2)
      ..lineTo(19.7, 19.4)
      ..quadraticBezierTo(21.5, 21.1, 21, 22.5)
      ..lineTo(5.8, 9.6)
      ..close()
      ..moveTo(5.8, 14.6)
      ..lineTo(21, 1.2)
      ..quadraticBezierTo(21.5, 2.5, 19.7, 4.4)
      ..lineTo(6.8, 16.7)
      ..close();
    final handles = Path()..fillType = PathFillType.evenOdd;
    for (final y in [6.8, 17.2]) {
      final center = Offset(4.6, y);
      handles
        ..addOval(Rect.fromCircle(center: center, radius: 3.2))
        ..addOval(Rect.fromCircle(center: center, radius: 1.55));
    }
    return Path.combine(PathOperation.union, blades, handles);
  }

  void _paintScissors(Canvas canvas) {
    final shadow = Color.lerp(
      color,
      Colors.black.withValues(alpha: color.a),
      .46,
    )!;
    final highlight = Color.lerp(
      color,
      Colors.white.withValues(alpha: color.a),
      .45,
    )!;
    final depth = Paint()..color = shadow;
    Paint face(Path path, List<Color> colors) {
      return Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: colors,
        ).createShader(path.getBounds());
    }

    canvas.drawPath(_scissors.shift(const Offset(.45, .8)), depth);
    canvas.drawPath(
      _scissors,
      face(_scissors, [Color.lerp(color, highlight, .5)!, color, shadow]),
    );
    canvas.drawCircle(const Offset(9.8, 11.7), .65, Paint()..color = highlight);
    canvas.drawPath(_note.shift(const Offset(.3, .8)), depth);
    canvas.drawPath(_note, face(_note, [highlight, color]));
  }

  void _paintClapperboard(Canvas canvas) {
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.7
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.drawRRect(
      RRect.fromLTRBR(3.6, 9.6, 21, 21.2, const Radius.circular(1.5)),
      stroke,
    );
    canvas.drawLine(const Offset(3.6, 13.1), const Offset(21, 13.1), stroke);
    canvas.drawLine(const Offset(7.4, 17.1), const Offset(17.2, 17.1), stroke);

    canvas.save();
    canvas.translate(3.6, 9.6);
    canvas.rotate(-.26);
    canvas.drawRRect(
      RRect.fromLTRBR(0, -3.6, 17.5, 0, const Radius.circular(.8)),
      stroke,
    );
    for (final x in [4.0, 9.0, 14.0]) {
      canvas.drawLine(Offset(x + 1.7, -3.6), Offset(x, 0), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_EditMediaPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.color != color;
}
