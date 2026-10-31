import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'motion.dart';

/// The folder moth, drawn in code. Coordinates match assets/logo.svg (200 x 200).
/// With [alive], the wings beat gently; faster while [busy].
class MothLogo extends StatefulWidget {
  const MothLogo({super.key, this.size = 40, this.ink, this.accent = const Color(0xFF2BB673), this.alive = false, this.busy = false});

  final double size;
  final Color? ink;
  final Color accent;
  final bool alive;
  final bool busy;

  @override
  State<MothLogo> createState() => _MothLogoState();
}

class _MothLogoState extends State<MothLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(MothLogo old) {
    super.didUpdateWidget(old);
    if (old.alive != widget.alive || old.busy != widget.busy) _sync();
  }

  void _sync() {
    final moving = (widget.alive || widget.busy) && !calm(context);
    if (!moving) {
      _c.animateTo(0, duration: const Duration(milliseconds: 300));
      return;
    }
    _c.duration = Duration(milliseconds: widget.busy ? 520 : 2600);
    _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.ink ?? Theme.of(context).colorScheme.onSurface;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => CustomPaint(
        size: Size.square(widget.size),
        painter: _MothPainter(color, widget.accent, math.sin(_c.value * 2 * math.pi)),
      ),
    );
  }
}

class _MothPainter extends CustomPainter {
  _MothPainter(this.ink, this.accent, this.beat);

  final Color ink;
  final Color accent;
  final double beat; // -1 .. 1

  static Path _wing({required bool left}) {
    final p = Path();
    if (left) {
      p
        ..moveTo(20, 64)
        ..quadraticBezierTo(20, 54, 30, 54)
        ..lineTo(58, 54)
        ..lineTo(67, 66)
        ..lineTo(94, 66)
        ..lineTo(94, 152)
        ..lineTo(30, 152)
        ..quadraticBezierTo(20, 152, 20, 142);
    } else {
      p
        ..moveTo(180, 64)
        ..quadraticBezierTo(180, 54, 170, 54)
        ..lineTo(142, 54)
        ..lineTo(133, 66)
        ..lineTo(106, 66)
        ..lineTo(106, 152)
        ..lineTo(170, 152)
        ..quadraticBezierTo(180, 152, 180, 142);
    }
    return p..close();
  }

  static final _left = _wing(left: true);
  static final _right = _wing(left: false);

  void _wingAt(Canvas c, Path path, double deg, Offset pivot, double squeeze, Paint paint) {
    c
      ..save()
      ..translate(pivot.dx, pivot.dy)
      ..rotate(deg * math.pi / 180)
      ..scale(squeeze, 1)
      ..translate(-pivot.dx, -pivot.dy)
      ..drawPath(path, paint)
      ..restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 200, size.height / 200);
    final fill = Paint()..color = ink;
    // A beat folds the wings in a little and tilts them up.
    final squeeze = 1 - 0.18 * beat.abs();
    final tilt = 6 * beat.abs();
    _wingAt(canvas, _left, -8 - tilt, const Offset(94, 104), squeeze, fill);
    _wingAt(canvas, _right, 8 + tilt, const Offset(106, 104), squeeze, fill);
    canvas.drawRRect(
      RRect.fromRectAndRadius(const Rect.fromLTWH(95, 50, 10, 112), const Radius.circular(5)),
      Paint()..color = accent,
    );
    final antenna = Paint()
      ..color = ink
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas
      ..drawLine(const Offset(98, 50), Offset(86 - 2 * beat, 30), antenna)
      ..drawLine(const Offset(102, 50), Offset(114 + 2 * beat, 30), antenna);
  }

  @override
  bool shouldRepaint(_MothPainter old) => old.ink != ink || old.accent != accent || old.beat != beat;
}
