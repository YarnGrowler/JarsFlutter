import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/super_reaction_meta.dart';
import '../../core/theme.dart';
import '../../models/exercise_log.dart';
import '../../models/reaction.dart';
import '../../models/room.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/achievement_post_log_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/score_provider.dart';
import '../../providers/room_provider.dart';
import '../../services/log_service.dart';
import '../../services/reaction_service.dart';
import '../../services/score_service.dart';
import '../../services/supabase_service.dart';
import '../../services/wake_nudge_service.dart';
import '../../widgets/feed/feed_card.dart';
import '../../widgets/sheets/group_goal_sheet.dart';
import '../../widgets/sheets/room_sheets.dart';
import '../../widgets/ui/member_avatar_ring.dart';
import '../../widgets/ui/confirm_delete_dialog.dart';
import '../../widgets/ui/rivalry_banner.dart';
import '../../widgets/ui/status_bar.dart';

class RoomScreen extends ConsumerStatefulWidget {
  const RoomScreen({super.key});

  @override
  ConsumerState<RoomScreen> createState() => _RoomScreenState();
}

class _RoomScreenState extends ConsumerState<RoomScreen> {
  @override
  Widget build(BuildContext context) {
    final room = ref.watch(activeRoomProvider);
    final scoresAsync = ref.watch(roomScoresProvider);
    final myScoreAsync = ref.watch(myScoreProvider);
    final feedAsync = ref.watch(roomFeedWithReactionsProvider);

    ref.listen<List<String>?>(achievementPostLogHintsProvider, (prev, next) {
      if (next == null || next.isEmpty) return;
      final text = next.length == 1
          ? next.first
          : '${next.take(3).join(' · ')}${next.length > 3 ? '…' : ''}';
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(text),
            duration: const Duration(seconds: 4),
          ),
        );
        ref.read(achievementPostLogHintsProvider.notifier).state = null;
      });
    });

    if (room == null) {
      return _buildNoRoom(context);
    }

    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          room.name,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 24,
                            fontWeight: FontWeight.w700,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _buildMemberAvatars(room),
                      ],
                    ),
                  ),
                  GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: room.roomCode));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Room code copied!'),
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: JarsColors.surface,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: JarsColors.border),
                      ),
                      child: Text(
                        room.roomCode,
                        style: GoogleFonts.spaceMono(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: JarsColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Rivalry Banner
            scoresAsync.when(
              data: (scores) {
                return myScoreAsync.when(
                  data: (myScore) {
                    if (myScore == null || scores.isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: RivalryBanner(
                        myScore: myScore,
                        allScores: scores,
                        onLogTap: () => context.go('/log'),
                      )
                          .animate()
                          .fadeIn(
                              duration: 380.ms, curve: Curves.easeOutCubic)
                          .slideY(
                              begin: 0.06,
                              end: 0,
                              duration: 380.ms,
                              curve: Curves.easeOutCubic),
                    );
                  },
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),

            // Live Feed
            Expanded(
              child: feedAsync.when(
                data: (items) {
                  if (items.isEmpty) {
                    return _buildEmptyFeed();
                  }
                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      RefreshIndicator(
                        color: JarsColors.primary,
                        onRefresh: () async {
                          ref.invalidate(roomFeedWithReactionsProvider);
                          ref.invalidate(roomFeedProvider);
                          ref.invalidate(roomScoresProvider);
                          ref.invalidate(myScoreProvider);
                          ref.invalidate(groupGoalProgressProvider);
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                          itemCount: items.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final row = items[index];
                            final delayMs = (index * 12).clamp(0, 96);
                            return _buildFeedItem(
                              context,
                              row.log,
                              row.reactions,
                            )
                                .animate()
                                .fadeIn(
                                  duration: 110.ms,
                                  delay: Duration(milliseconds: delayMs),
                                  curve: Curves.easeOut,
                                )
                                .slideY(
                                  begin: 0.028,
                                  duration: 110.ms,
                                  delay: Duration(milliseconds: delayMs),
                                  curve: Curves.easeOut,
                                );
                          },
                        ),
                      ),
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: 28,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  JarsColors.background,
                                  JarsColors.background.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        bottom: 0,
                        left: 0,
                        right: 0,
                        height: 36,
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                                colors: [
                                  JarsColors.background,
                                  JarsColors.background.withValues(alpha: 0),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
                loading: () => const Center(
                  child:
                      CircularProgressIndicator(color: JarsColors.primary),
                ),
                error: (e, _) => Center(
                  child: Text('Error: $e',
                      style: GoogleFonts.inter(
                          color: JarsColors.textSecondary)),
                ),
              ),
            ),

            // Status Bar
            myScoreAsync.when(
              data: (score) {
                final uid = SupabaseService.currentUserId;
                final isAdmin =
                    uid != null && uid == room.adminId;
                return StatusBar(
                  onLogTap: () => context.go('/log'),
                  onGroupGoalTap: isAdmin
                      ? () => showGroupGoalSheet(context, room.id)
                      : null,
                );
              },
              loading: () => const SizedBox.shrink(),
              error: (_, __) => const SizedBox.shrink(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberAvatars(Room room) {
    final uid = SupabaseService.currentUserId;
    final isAdmin = uid != null && uid == room.adminId;

    final membersAsync = ref.watch(roomMembersProvider(room.id));

    return membersAsync.when(
      data: (members) {
        const maxFaces = 15;
        const overlap = 9.0;
        const size = 26.0;
        final n = members.length;
        final showOverflow = n > maxFaces;
        final faceCount = showOverflow ? maxFaces - 1 : n;
        final overflowCount = showOverflow ? n - (maxFaces - 1) : 0;
        final colors = [
          JarsColors.primary,
          JarsColors.gold,
          JarsColors.green,
          JarsColors.red,
          const Color(0xFFAFEEEE),
          const Color(0xFFBA55D3),
        ];

        return GestureDetector(
          onTap: isAdmin && members.isNotEmpty
              ? () => showRoomMembersAdminSheet(context, ref, room)
              : null,
          behavior: HitTestBehavior.translucent,
          child: SizedBox(
            height: size,
            child: Row(
              children: [
                for (var i = 0; i < faceCount; i++)
                  Transform.translate(
                    offset: Offset(-i * overlap, 0),
                    child: MemberAvatarCircle(
                      initial: _getInitial(members[i]),
                      color: colors[i % colors.length],
                      size: size,
                    ),
                  ),
                if (showOverflow)
                  Transform.translate(
                    offset: Offset(-faceCount * overlap, 0),
                    child: MemberOverflowAvatar(
                      overflowCount: overflowCount,
                      size: size,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox(height: 26),
      error: (_, __) => const SizedBox(height: 26),
    );
  }

  String _getInitial(Map<String, dynamic> member) {
    final profiles = member['profiles'];
    if (profiles != null && profiles is Map && profiles['username'] != null) {
      return (profiles['username'] as String).substring(0, 1).toUpperCase();
    }
    return '?';
  }

  Widget _buildFeedItem(
      BuildContext context, ExerciseLog log, List<Reaction> reactions) {
    final room = ref.watch(activeRoomProvider);
    final uid = SupabaseService.currentUserId;
    final isAdmin =
        room != null && uid != null && uid == room.adminId;

    final card = FeedCard(
      log: log,
      reactions: reactions,
      onReact: (log.isWakeCard ||
              log.isFirstLog ||
              log.isMemberJoin ||
              log.isMemberKick)
          ? null
          : (emoji) async {
              try {
                SuperReactionDef? superDef;
                if (isSuperReactionKey(emoji)) {
                  superDef = tryParseSuperReaction(emoji);
                  if (superDef == null) return;
                  if (room == null || uid == null) return;
                  final score = await ScoreService.getUserScore(room.id, uid);
                  if (score == null ||
                      score.totalScore < superDef.cost) {
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Need ${superDef.cost} points (you have '
                          '${score?.totalScore.floor() ?? 0}).',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                    return;
                  }
                }

                final added = await ReactionService.addReaction(
                  logId: log.id,
                  emoji: emoji,
                );
                if (added != null && superDef != null && room != null) {
                  await ScoreService.subtractPoints(
                    roomId: room.id,
                    points: superDef.cost.toDouble(),
                  );
                }
                ref.invalidate(roomFeedWithReactionsProvider);
                ref.invalidate(roomFeedProvider);
                ref.invalidate(myScoreProvider);
              } catch (e) {
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('Reaction failed: $e'),
                      duration: const Duration(seconds: 2)),
                );
              }
            },
      onWakeNudge: log.isWakeCard && uid != null && uid != log.userId
          ? () async {
              final err = await WakeNudgeService.nudgeAbsentMember(log);
              if (!context.mounted) return;
              if (err != null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(err)),
                );
                return;
              }
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'Ping sent to ${log.username ?? 'them'}',
                    style: GoogleFonts.inter(),
                  ),
                ),
              );
            }
          : null,
    );

    // Nest AI reply cards under the thread (visual reply indentation).
    final Widget paddedCard =
        log.isAiReply
            ? Padding(
                padding: const EdgeInsets.only(left: 14),
                child: card,
              )
            : card;

    if (!isAdmin) return paddedCard;

    return Dismissible(
      key: ValueKey('admin-dismiss-${log.id}'),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 22),
        decoration: BoxDecoration(
          color: const Color(0xFFC43C3C),
          borderRadius: BorderRadius.circular(JarsRadius.card),
        ),
        child: Text(
          'Delete',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ),
      confirmDismiss: (direction) async {
        final ok = await showConfirmDeleteFeedMessage(context);
        if (!ok) return false;
        try {
          await LogService.deleteLog(log.id);
          ref.invalidate(roomFeedWithReactionsProvider);
          ref.invalidate(roomFeedProvider);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Message removed from room feed'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return true;
        } catch (e) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Could not delete: $e'),
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return false;
        }
      },
      child: paddedCard,
    );
  }

  Widget _buildEmptyFeed() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🏋️', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          Text(
            'Suspiciously quiet.',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: JarsColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "Either everyone's resting or plotting.",
            style: GoogleFonts.inter(
              fontSize: 14,
              color: JarsColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoRoom(BuildContext context) {
    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('⚔️', style: TextStyle(fontSize: 48)),
              const SizedBox(height: 16),
              Text(
                'No room yet',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: JarsColors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Create or join a room to start competing.',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: JarsColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: () => showCreateRoomSheet(context),
                  child: Text(
                    'Create a room',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton(
                  onPressed: () => showJoinRoomSheet(context),
                  child: Text(
                    'Join with code',
                    style: GoogleFonts.spaceGrotesk(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => context.go('/auth/room-entry'),
                child: Text(
                  'More options',
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    color: JarsColors.textTertiary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
