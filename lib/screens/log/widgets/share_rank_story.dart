import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/log_screen_style.dart';
import '../../../models/level.dart';

/// 1080×1920 story layout for export (must match spec proportions in logical px).
class ShareRankStory extends StatelessWidget {
  final Level level;
  final String username;
  final double totalPoints;

  const ShareRankStory({
    super.key,
    required this.level,
    required this.username,
    required this.totalPoints,
  });

  @override
  Widget build(BuildContext context) {
    final pts = totalPoints % 1 == 0
        ? totalPoints.toStringAsFixed(0)
        : totalPoints.toStringAsFixed(1);

    return DecoratedBox(
      decoration: const BoxDecoration(color: kLogNearBlack),
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(
              width: 4,
              color: level.color,
            ),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 200,
                    height: 200,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: level.color.withValues(alpha: 0.2),
                      border: Border.all(color: level.color, width: 3),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      level.icon,
                      style: const TextStyle(fontSize: 88),
                    ),
                  ),
                  const SizedBox(height: 36),
                  Text(
                    username,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 48,
                      fontWeight: FontWeight.w700,
                      color: kLogText,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    level.title,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: level.color,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    level.description,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 20,
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.italic,
                      color: kLogText.withValues(alpha: 0.6),
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    '$pts pts',
                    style: GoogleFonts.spaceMono(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: kLogGold,
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            right: 32,
            bottom: 40,
            child: Text(
              'JARS',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: kLogText.withValues(alpha: 0.35),
                letterSpacing: 3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
