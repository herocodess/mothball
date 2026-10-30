import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The folder moth, drawn in code so the app needs no image assets.
/// Coordinates match assets/logo.svg (a 200 x 200 box).
class MothLogo extends StatelessWidget {
  const MothLogo({super.key, this.size = 40, this.ink, this.accent = const Color(0xFF2BB673)});

  final double size;
  final Color? ink;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final color = ink ?? Theme.of(context).colorScheme.onSurface;
    return CustomPaint(size: Size.square(size), painter: _MothPainter(color, accent));
  }
}

class _MothPainter extends CustomPainter {
  _MothPainter(this.ink, this.accent);

  final Color ink;
  final Color accent;

  Path _wing({required bool left}) {
    final p = Path();
    if (left) {
      p.moveTo(20, 64);
      p.quadraticBezierTo(20, 54, 30, 54);
      p.lineTo(58, 54);
      p.lineTo(67, 66);
      p.lineTo(94, 66);
      p.lineTo(94, 152);
      p.lineTo(30, 152);
      p.quadraticBezierTo(20, 152, 20, 142);
    } else {
      p.moveTo(180, 64);
      p.quadraticBezierTo(180, 54, 170, 54);
      p.lineTo(142, 54);
      p.lineTo(133, 66);
      p.lineTo(106, 66);
      p.lineTo(106, 152);
      p.lineTo(170, 152);
      p.quadraticBezierTo(180, 152, 180, 142);
    }
    p.close();
    return p;
  }

  void _rotated(Canvas c, double deg, Offset pivot, void Function() draw) {
    c.save();
    c.translate(pivot.dx, pivot.dy);
    c.rotate(deg * math.pi / 180);
    c.translate(-pivot.dx, -pivot.dy);
    draw();
    c.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 200, size.height / 200);
    final fill = Paint()..color = ink;
    _rotated(canvas, -8, const Offset(94, 104), () => canvas.drawPath(_wing(left: true), fill));
    _rotated(canvas, 8, const Offset(106, 104), () => canvas.drawPath(_wing(left: false), fill));
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(95, 50, 10, 112), const Radius.circular(5)),
      Paint()..color = accent,
    );
    final antenna = Paint()
      ..color = ink
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(const Offset(98, 50), const Offset(86, 30), antenna);
    canvas.drawLine(const Offset(102, 50), const Offset(114, 30), antenna);
  }

  @override
  bool shouldRepaint(_MothPainter old) => old.ink != ink || old.accent != accent;
}
