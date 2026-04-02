import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/level.dart';

class RankBadge extends StatelessWidget {
  final Level level;
  final double size;
  final bool showTitle;

  const RankBadge({
    super.key,
    required this.level,
    this.size = 40,
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: level.color.withValues(alpha: 0.15),
            border: Border.all(color: level.color, width: 2),
          ),
          child: Center(
            child: Text(
              level.icon,
              style: TextStyle(fontSize: size * 0.45),
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
