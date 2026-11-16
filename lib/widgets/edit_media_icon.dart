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

  static final Path _note = _makeNote();

  /// 가위의 두 쪽. [_bladeBack] 은 오른쪽 위로 뻗는 날(아래 손잡이), [_bladeFront] 는 오른쪽 아래로 뻗는 날(위 손잡이).
  static final Path _bladeBack = _makeHalf(up: true);
  static final Path _bladeFront = _makeHalf(up: false);

  /// 8분음표. 기둥이 두 가윗날 사이를 지나가고, 머리는 아랫날 밑에, 꼬리는 윗날 위에 온다.
  static Path _makeNote() {
    final stemAndFlag = Path()
      ..moveTo(15.2, 1.3)
      ..lineTo(16.9, 1.3)
      ..cubicTo(17.9, 3.0, 21.2, 3.0, 21.8, 5.9)
      ..quadraticBezierTo(22.1, 7.2, 21.4, 8.3)
      ..quadraticBezierTo(20.9, 4.9, 16.9, 3.9)
      ..lineTo(16.9, 20.2)
      ..lineTo(15.2, 20.2)
      ..close();
    final head = Path()
      ..addOval(Rect.fromCenter(center: Offset.zero, width: 5.8, height: 4.1));
    final m = Matrix4.identity()
      ..translateByDouble(14.1, 20.2, 0, 1)
      ..rotateZ(-.38);
    return Path.combine(
      PathOperation.union,
      stemAndFlag,
      head.transform(m.storage),
    );
  }

  /// 가위 한 쪽(날 + 손잡이). 날을 눕혀서(기울기 약 30도) 기둥을 옆에서 무는 모양이 되게 한다.
  /// [up] 이면 위아래를 뒤집은 쪽.
  static Path _makeHalf({required bool up}) {
    double y(double v) => up ? 24 - v : v;
    final blade = Path()
      ..moveTo(6.2, y(8.0))
      ..lineTo(18.3, y(15.0))
      ..quadraticBezierTo(19.9, y(16.1), 19.8, y(17.4))
      ..lineTo(5.8, y(10.2))
      ..close();
    final center = Offset(4.6, y(7.4));
    final handle = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(Rect.fromCircle(center: center, radius: 3.2))
      ..addOval(Rect.fromCircle(center: center, radius: 1.55));
    return Path.combine(PathOperation.union, blade, handle);
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

    void solid(Path path, List<Color> colors, Offset drop) {
      canvas.drawPath(path.shift(drop), depth);
      canvas.drawPath(path, face(path, colors));
    }

    // 뒤에서 앞으로: 윗날 -> 음표 -> 아랫날. 기둥이 윗날 앞, 아랫날 뒤에 놓여 두 날 사이에 끼인 것처럼 보인다.
    // 겹치는 곳에서는 위에 오는 것의 둘레를 가늘게 비워 둔다. 그래야 앞뒤가 또렷하고 작게 봐도 읽힌다.
    final gap = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeJoin = StrokeJoin.round;
    void carve(Path path, Offset drop) {
      canvas.drawPath(path, gap);
      canvas.drawPath(path.shift(drop), gap);
    }

    const noteDrop = Offset(.4, .8);
    const bladeDrop = Offset(.45, .8);
    final metal = [Color.lerp(color, highlight, .5)!, color, shadow];
    // 비우기(clear)가 아이콘 뒤 배경까지 지우지 않게 따로 그린 뒤 얹는다.
    canvas.saveLayer(const Rect.fromLTWH(-1, -1, 26, 26), Paint());
    solid(_bladeBack, metal, bladeDrop);
    carve(_note, noteDrop);
    solid(_note, [highlight, color], noteDrop);
    // 앞날은 기둥과 만나는 곳만 비운다(두 날이 만나는 축 쪽은 그대로 붙여 둔다).
    canvas.save();
    canvas.clipRect(const Rect.fromLTRB(14.2, 8, 18.6, 20));
    carve(_bladeFront, bladeDrop);
    canvas.restore();
    solid(_bladeFront, metal, bladeDrop);
    canvas.drawCircle(const Offset(11.2, 12), .7, Paint()..color = highlight);
    canvas.restore();
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
