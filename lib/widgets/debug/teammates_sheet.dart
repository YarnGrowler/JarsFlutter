import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/war_providers.dart';

/// Your clan roster (Demo Mode: local). Each teammate is a character who fights
/// in the Clan War — build the base together, raid the enemy together.
Future<void> showTeammatesSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: JarsColors.surfaceRaised,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (_) => const _TeammatesSheet(),
  );
}

class _TeammatesSheet extends ConsumerWidget {
  const _TeammatesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final g = ref.watch(warGameProvider);
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
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('Your Clan',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: JarsColors.textPrimary)),
            const SizedBox(height: 4),
            Text(
                'Each teammate is a character in the Clan War. Tap "Playing as" on '
                'the War tab to control any of them for the demo.',
                style: GoogleFonts.inter(
                    fontSize: 13, height: 1.4, color: JarsColors.textSecondary)),
            const SizedBox(height: 12),
            for (final p in g.youClan)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  Text(p.emoji, style: const TextStyle(fontSize: 24)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.isYou ? '${p.name} (you)' : p.name,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: JarsColors.textPrimary)),
                        Text('⚡ ${g.resourcesOf(p.id).round()} points',
                            style: GoogleFonts.spaceMono(
                                fontSize: 12, color: JarsColors.gold)),
                      ],
                    ),
                  ),
                  if (p.id == g.activePlayerId)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: JarsColors.primary.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(9999),
                      ),
                      child: Text('CONTROLLING',
                          style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: JarsColors.primary)),
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }
}
