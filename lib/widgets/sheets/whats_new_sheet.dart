import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';

/// Shown once after the co-op redesign. Names what changed (to rebuild trust
/// with a crew that left) and offers a one-tap way to bring them back.
Future<void> showWhatsNewSheet(BuildContext context, {String? roomCode}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JarsColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => _WhatsNewContent(roomCode: roomCode),
  );
}

class _WhatsNewContent extends StatelessWidget {
  final String? roomCode;
  const _WhatsNewContent({this.roomCode});

  static const List<(String, String, String)> _changes = [
    (
      '🏆',
      'A real league',
      'Your room is a team in a league. Beat AI teams each week, and get '
          'promoted or relegated at the end of the season.',
    ),
    (
      '🤝',
      'No more shame',
      'No streak-shaming, no ghost "hasn\'t logged" cards, no "you\'re losing '
          'ground". A quiet week is okay.',
    ),
    (
      '🔥',
      'Forgiving streaks',
      'A rest day no longer nukes your streak. Life happens.',
    ),
    (
      '⚡',
      'Faster logging',
      'Tap your points to log — no more holding the screen for two seconds.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: JarsColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(
              'Jars is different now 🏆',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: JarsColors.textPrimary,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'We rebuilt it around your team and a real league.',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: JarsColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            for (final c in _changes) ...[
              _row(c.$1, c.$2, c.$3),
              const SizedBox(height: 14),
            ],
            const SizedBox(height: 4),
            if (roomCode != null) ...[
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(
                      text: "Come back to Jars — it's different now. "
                          'We climb a league together as a team now, no more '
                          'streak shaming. Join my crew with code $roomCode',
                    ));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Invite copied — paste it to your crew'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Text(
                    'Bring your crew back',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            SizedBox(
              width: double.infinity,
              height: 50,
              child: TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  "Let's go",
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                    color: JarsColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row(String emoji, String title, String body) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 22)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: JarsColors.textPrimary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                body,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  height: 1.35,
                  color: JarsColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
