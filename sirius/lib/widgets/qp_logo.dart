import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Minimal geometric logo for 穹沛科技 (Qiongpei Technology).
///
/// Draws a clean dome arc (穹 = sky/dome) with a single dot beneath
/// (沛 = flow/abundance). Works well at 16 px (title bar) and 24 px (splash).
class QpLogo extends StatelessWidget {
  final double size;
  final Color? color;

  const QpLogo({super.key, this.size = 16, this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _QpLogoPainter(color: color ?? IconTheme.of(context).color ?? Colors.white)),
    );
  }
}

class _QpLogoPainter extends CustomPainter {
  final Color color;

  _QpLogoPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width; // square canvas

    // ── Dome arc ──────────────────────────────────────────────────
    // A 180° arc spanning ~80 % of width, vertically centered in
    // the upper 60 % of the canvas.
    final arcStroke = (s * 0.14).clamp(1.5, 4.0);
    final arcPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = arcStroke
      ..strokeCap = StrokeCap.round;

    final arcHalfW = s * 0.38; // half-width of the arc
    final arcCenterX = s * 0.5;
    final arcCenterY = s * 0.42;
    final arcRect = Rect.fromCenter(
      center: Offset(arcCenterX, arcCenterY),
      width: arcHalfW * 2,
      height: arcHalfW * 2,
    );

    // Draw top 180° arc (from pi to 2*pi, i.e. left-to-right over the top)
    canvas.drawArc(arcRect, math.pi, math.pi, false, arcPaint);

    // ── Dot (沛 = flow) ──────────────────────────────────────────
    final dotRadius = (s * 0.075).clamp(1.0, 3.0);
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final dotCenter = Offset(arcCenterX, arcCenterY + arcHalfW + s * 0.14);
    canvas.drawCircle(dotCenter, dotRadius, dotPaint);
  }

  @override
  bool shouldRepaint(_QpLogoPainter old) => old.color != color;
}
