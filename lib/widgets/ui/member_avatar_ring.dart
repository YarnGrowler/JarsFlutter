import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';

/// Colors for member piles (stable order; index wraps).
const List<Color> kMemberAvatarColors = [
  JarsColors.primary,
  JarsColors.gold,
  JarsColors.green,
  JarsColors.red,
  Color(0xFF5EC8D8),
  Color(0xFFBA55D3),
  Color(0xFFFF8A65),
  Color(0xFF81C784),
  Color(0xFF64B5F6),
  Color(0xFFFFB74D),
  Color(0xFFA1887F),
  Color(0xFF90A4AE),
  Color(0xFFF06292),
  Color(0xFF7986CB),
  Color(0xFF4DD0E1),
];

Color memberColorForIndex(int i) =>
    kMemberAvatarColors[i % kMemberAvatarColors.length];

/// Single initial avatar (room header, lists).
class MemberAvatarCircle extends StatelessWidget {
  final String initial;
  final Color color;
  final double size;
  final bool showBorder;

  const MemberAvatarCircle({
    super.key,
    required this.initial,
    required this.color,
    this.size = 24,
    this.showBorder = true,
  });

  @override
  Widget build(BuildContext context) {
    final letter = initial.isNotEmpty ? initial[0].toUpperCase() : '?';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
        border: showBorder
            ? Border.all(color: JarsColors.background, width: 2)
            : null,
      ),
      alignment: Alignment.center,
      child: Text(
        letter,
        style: GoogleFonts.inter(
          fontSize: size * 0.42,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}

/// Last chip in a pile: "+N" styled like an avatar.
class MemberOverflowAvatar extends StatelessWidget {
  final int overflowCount;
  final double size;

  const MemberOverflowAvatar({
    super.key,
    required this.overflowCount,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    final label = '+$overflowCount';
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: JarsColors.surfaceRaised,
        border: Border.all(color: JarsColors.background, width: 2),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: overflowCount >= 10 ? size * 0.28 : size * 0.34,
          fontWeight: FontWeight.w700,
          color: JarsColors.textPrimary,
          height: 1,
        ),
        maxLines: 1,
      ),
    );
  }
}
