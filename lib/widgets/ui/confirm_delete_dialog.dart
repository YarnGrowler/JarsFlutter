import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';

Future<bool> showConfirmDeleteFeedMessage(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: JarsColors.surfaceRaised,
      title: Text(
        'Remove from feed?',
        style: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: JarsColors.textPrimary,
        ),
      ),
      content: Text(
        'This deletes the message for everyone in the room. This cannot be undone.',
        style: GoogleFonts.inter(
          fontSize: 14,
          height: 1.35,
          color: JarsColors.textSecondary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Cancel',
            style: GoogleFonts.inter(color: JarsColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Delete',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: const Color(0xFFE85D5D),
            ),
          ),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<bool> showConfirmDeleteWorkoutLog(BuildContext context) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: JarsColors.surfaceRaised,
      title: Text(
        'Delete this log?',
        style: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: JarsColors.textPrimary,
        ),
      ),
      content: Text(
        'Your points for this workout will be subtracted from the room. This cannot be undone.',
        style: GoogleFonts.inter(
          fontSize: 14,
          height: 1.35,
          color: JarsColors.textSecondary,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(
            'Cancel',
            style: GoogleFonts.inter(color: JarsColors.textSecondary),
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(
            'Delete',
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w700,
              color: const Color(0xFFE85D5D),
            ),
          ),
        ),
      ],
    ),
  );
  return r ?? false;
}
