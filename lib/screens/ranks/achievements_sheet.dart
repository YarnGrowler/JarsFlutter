import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/achievement_catalog.dart';
import '../../core/achievement_ui_helpers.dart';
import '../../core/theme.dart';
import '../../services/achievement_service.dart';
import '../../services/supabase_service.dart';

/// Per-user achievement gallery for the active room.
class AchievementsSheet extends ConsumerStatefulWidget {
  final String roomId;

  const AchievementsSheet({super.key, required this.roomId});

  @override
  ConsumerState<AchievementsSheet> createState() => _AchievementsSheetState();
}

class _AchievementsSheetState extends ConsumerState<AchievementsSheet> {
  List<Map<String, dynamic>>? _progress;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = SupabaseService.currentUserId;
    if (uid == null) {
      setState(() {
        _loading = false;
        _error = 'Not signed in';
      });
      return;
    }
    try {
      await AchievementService.markAchievementsOpened(roomId: widget.roomId, userId: uid);
      final rows = await AchievementService.getMyProgress(widget.roomId, uid);
      if (mounted) {
        setState(() {
          _progress = rows;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  int _tierFor(String key) {
    final rows = _progress;
    if (rows == null) return 0;
    for (final r in rows) {
      if (r['achievement_key'] == key) {
        return AchievementService.normalizeTierReached(r['tier_reached']);
      }
    }
    return 0;
  }

  Map<String, dynamic>? _progressJsonFor(String key) {
    final rows = _progress;
    if (rows == null) return null;
    for (final r in rows) {
      if (r['achievement_key'] == key) {
        final p = r['progress'];
        if (p is Map<String, dynamic>) return p;
        return null;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.45,
      maxChildSize: 0.96,
      builder: (_, controller) => Container(
        decoration: BoxDecoration(
          color: JarsColors.background,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Achievements',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Tier goals match the server. Log a workout to update progress.',
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            height: 1.3,
                            color: JarsColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    color: JarsColors.textSecondary,
                    onPressed: () {
                      setState(() {
                        _loading = true;
                        _progress = null;
                      });
                      _load();
                    },
                  ),
                ],
              ),
            ),
            if (_loading)
              const Expanded(
                child: Center(
                  child: CircularProgressIndicator(color: JarsColors.primary),
                ),
              )
            else if (_error != null)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _error!,
                      style: GoogleFonts.inter(color: JarsColors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  itemCount: kAchievementCatalog.length,
                  itemBuilder: (context, i) {
                    final def = kAchievementCatalog[i];
                    final tier = _tierFor(def.key);
                    final maxT = def.tiers.length;
                    final isFuture = maxT == 0;
                    return _AchievementGalleryCard(
                      entry: def,
                      tierReached: tier,
                      maxTiers: maxT,
                      isFutureWave: isFuture,
                      progressJson: _progressJsonFor(def.key),
                    )
                        .animate()
                        .fadeIn(duration: 280.ms, delay: (24 * i).ms)
                        .slideY(begin: 0.04, curve: Curves.easeOutCubic);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AchievementGalleryCard extends StatelessWidget {
  final AchievementCatalogEntry entry;
  final int tierReached;
  final int maxTiers;
  final bool isFutureWave;
  final Map<String, dynamic>? progressJson;

  const _AchievementGalleryCard({
    required this.entry,
    required this.tierReached,
    required this.maxTiers,
    required this.isFutureWave,
    this.progressJson,
  });

  @override
  Widget build(BuildContext context) {
    final unlocked = tierReached > 0;
    final accent = unlocked ? JarsColors.primary : JarsColors.textTertiary;
    final nextCondition = maxTiers > 0 && !isFutureWave
        ? achievementNextTierConditionLine(
            def: entry,
            tierReached: tierReached,
          )
        : '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: JarsColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: unlocked
                ? JarsColors.primary.withValues(alpha: 0.28)
                : JarsColors.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.emoji, style: const TextStyle(fontSize: 28)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.displayName,
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: JarsColors.textPrimary,
                              ),
                            ),
                          ),
                          if (isFutureWave)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: JarsColors.surfaceRaised,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Coming soon',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: JarsColors.textTertiary,
                                ),
                              ),
                            )
                          else if (entry.wave >= 2)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: JarsColors.surfaceRaised,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'Wave ${entry.wave}',
                                style: GoogleFonts.inter(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: JarsColors.textTertiary,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.description,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          height: 1.35,
                          color: JarsColors.textSecondary,
                        ),
                      ),
                      if (nextCondition.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            nextCondition,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              height: 1.35,
                              color: JarsColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            if (maxTiers > 0) ...[
              const SizedBox(height: 12),
              Row(
                children: List.generate(maxTiers, (j) {
                  final done = tierReached >= j + 1;
                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(right: j < maxTiers - 1 ? 6 : 0),
                      child: Column(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: done ? 1 : 0,
                              minHeight: 6,
                              backgroundColor: JarsColors.border,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            entry.tiers[j].roman,
                            style: GoogleFonts.spaceMono(
                              fontSize: 10,
                              color: done
                                  ? JarsColors.textPrimary
                                  : JarsColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tierReached >= maxTiers
                        ? 'Completed ✓'
                        : 'Tier $tierReached / $maxTiers',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      color: tierReached >= maxTiers
                          ? JarsColors.primary
                          : JarsColors.textTertiary,
                    ),
                  ),
                  if (tierReached < maxTiers) ...[
                    Text(
                      achievementTierProgressText(
                        def: entry,
                        tierReached: tierReached,
                        progressJson: progressJson,
                      ),
                      style: GoogleFonts.spaceMono(
                        fontSize: 10,
                        color: JarsColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
