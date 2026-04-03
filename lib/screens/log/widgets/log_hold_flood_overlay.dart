import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/log_screen_style.dart';

/// Full-screen purple flood from [originGlobal], expanding in discrete steps.
class LogHoldFloodOverlay extends StatelessWidget {
  final Offset originGlobal;
  final Animation<double> expansion;
  /// Stair-step count (higher = smoother, lower = chunkier).
  static const int stepCount = 18;

  const LogHoldFloodOverlay({
    super.key,
    required this.originGlobal,
    required this.expansion,
  });

  static double _coverRadius(Offset o, Size s) {
    double d(Offset c) => (c - o).distance;
    return math.max(
      math.max(d(Offset.zero), d(Offset(s.width, 0))),
      math.max(d(Offset(0, s.height)), d(Offset(s.width, s.height))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final render = context.findRenderObject() as RenderBox?;
        final originLocal = (render != null && render.attached)
            ? render.globalToLocal(originGlobal)
            : originGlobal;
        final maxR = _coverRadius(originLocal, c.biggest);

        return AnimatedBuilder(
          animation: expansion,
          builder: (_, __) {
            final raw = Curves.easeInCubic.transform(expansion.value);
            final stepped =
                (raw * stepCount).floor().clamp(0, stepCount) / stepCount;
            final r = maxR * stepped + 8;

            return CustomPaint(
              size: c.biggest,
              painter: _FloodPainter(
                origin: originLocal,
                radius: r,
              ),
            );
          },
        );
      },
    );
  }
}

class _FloodPainter extends CustomPainter {
  final Offset origin;
  final double radius;

  _FloodPainter({required this.origin, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final clip = Path()
      ..addOval(Rect.fromCircle(center: origin, radius: radius));
    canvas.clipPath(clip);

    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    final bg = Paint()
      ..shader = RadialGradient(
        colors: [
          kLogPurple.withValues(alpha: 0.98),
          kLogPurple.withValues(alpha: 0.88),
          const Color(0xFF5A4FD4).withValues(alpha: 0.95),
        ],
        stops: const [0.0, 0.45, 1.0],
      ).createShader(Rect.fromCircle(center: origin, radius: radius));

    canvas.drawRect(rect, bg);

    final veil = Paint()..color = Colors.black.withValues(alpha: 0.06);
    canvas.drawRect(rect, veil);
  }

  @override
  bool shouldRepaint(covariant _FloodPainter oldDelegate) =>
      oldDelegate.origin != origin || oldDelegate.radius != radius;
}
