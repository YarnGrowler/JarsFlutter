import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../models/level.dart';
import '../../widgets/ui/rank_badge.dart';

class RankUpCard extends StatelessWidget {
  final String username;
  final Level level;
  final DateTime timestamp;

  const RankUpCard({
    super.key,
    required this.username,
    required this.level,
    required this.timestamp,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: JarsColors.surface,
        borderRadius: BorderRadius.circular(JarsRadius.card),
        border: Border.all(color: JarsColors.gold, width: 2),
        boxShadow: [
          BoxShadow(
            color: JarsColors.goldDim,
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
      ),
      child: Column(
        children: [
          RankBadge(level: level, size: 56, showTitle: false),
          const SizedBox(height: 12),
          Text(
            '$username ranked up!',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: JarsColors.gold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            level.title,
            style: GoogleFonts.spaceMono(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: level.color,
            ),
          ),
        ],
      ),
    );
  }
}
