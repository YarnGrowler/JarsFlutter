import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/level_data.dart';
import '../../models/level.dart';

/// Rank icon with optional **progress arc** (like Ranks breakdown ring).
/// When [totalScore] is set, only a segment of the border reflects progress
/// toward the next rank threshold.
class RankBadge extends StatelessWidget {
  final Level level;
  final double size;
  final bool showTitle;

  /// If set, draws an arc progress ring (same semantics as [RankProgressArc]).
  final double? totalScore;

  const RankBadge({
    super.key,
    required this.level,
    this.size = 40,
    this.showTitle = true,
    this.totalScore,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalScore != null
        ? getProgressToNextLevel(totalScore!)
        : null;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(
              levelColor: level.color,
              progress: progress,
            ),
            child: Center(
              child: Text(
                level.icon,
                style: TextStyle(fontSize: size * 0.45),
              ),
            ),
          ),
        ),
        if (showTitle) ...[
          const SizedBox(width: 8),
          Text(
            level.title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: level.color,
            ),
          ),
        ],
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color levelColor;
  /// null = full ring (legacy solid border look)
  final double? progress;

  _RingPainter({required this.levelColor, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 1.5;
    const stroke = 2.5;

    if (progress == null) {
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = levelColor.withValues(alpha: 0.15)
          ..style = PaintingStyle.fill,
      );
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = levelColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = stroke,
      );
      return;
    }

    // Track (dim full ring)
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = levelColor.withValues(alpha: 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke,
    );

    // Progress arc (same angles as RankProgressArc)
    const startAngle = math.pi * 0.75;
    const sweepAngle = math.pi * 1.5;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle * progress!.clamp(0.0, 1.0),
      false,
      Paint()
        ..color = levelColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.levelColor != levelColor || old.progress != progress;
}
