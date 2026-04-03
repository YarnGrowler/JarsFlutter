import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../core/level_data.dart';
import '../../models/room.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/room_provider.dart';
import '../../providers/score_provider.dart';
import '../../providers/streak_provider.dart';
import '../../services/auth_service.dart';
import '../../services/badge_service.dart';
import '../../services/room_service.dart';
import '../../services/exercise_service.dart';
import '../../services/goal_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../models/badge.dart';
import '../../providers/exercise_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/profile_provider.dart';
import '../../core/user_display_name.dart';
import '../../widgets/ui/rank_badge.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = AuthService.currentUser;
    final profileAsync = ref.watch(currentUserProfileProvider);
    final displayName = profileAsync.maybeWhen(
      data: (p) => p?.username,
      orElse: () => null,
    ) ??
        displayNameFromUserMetadata(user) ??
        'Unknown';
    final scoreAsync = ref.watch(myScoreProvider);
    final streak = ref.watch(currentStreakProvider);
    final highestStreak = ref.watch(highestStreakProvider);
    final roomsAsync = ref.watch(userRoomsProvider);
    final activeRoom = ref.watch(activeRoomProvider);

    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayName,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        scoreAsync.when(
                          data: (score) {
                            if (score == null) return const SizedBox.shrink();
                            final level =
                                getLevelForScore(score.totalScore);
                            return RankBadge(level: level, size: 32);
                          },
                          loading: () => const SizedBox.shrink(),
                          error: (_, __) => const SizedBox.shrink(),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => _showSettings(context, ref),
                    icon: const Icon(Icons.settings_outlined,
                        color: JarsColors.textSecondary),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // 4 Stats grid
              Row(
                children: [
                  _StatCard(
                    icon: '🔥',
                    label: 'Streak',
                    value: '$streak days',
                  ),
                  const SizedBox(width: 12),
                  _StatCard(
                    icon: '📈',
                    label: 'All Time',
                    value: scoreAsync.maybeWhen(
                      data: (s) =>
                          '${(s?.totalScore ?? 0).toInt()} pts',
                      orElse: () => '...',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _StatCard(
                    icon: '🏆',
                    label: 'Best Streak',
                    value: '$highestStreak days',
                  ),
                  const SizedBox(width: 12),
                  scoreAsync.when(
                    data: (score) {
                      if (score == null) {
                        return _StatCard(
                          icon: '💎',
                          label: 'Rank',
                          value: 'None',
                        );
                      }
                      final level =
                          getLevelForScore(score.totalScore);
                      return _StatCard(
                        icon: level.icon,
                        label: 'Rank',
                        value: level.title,
                      );
                    },
                    loading: () => _StatCard(
                      icon: '💎',
                      label: 'Rank',
                      value: '...',
                    ),
                    error: (_, __) => _StatCard(
                      icon: '💎',
                      label: 'Rank',
                      value: 'Error',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Rooms section
              Text(
                'Rooms',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: JarsColors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              roomsAsync.when(
                data: (rooms) {
                  if (rooms.isEmpty) {
                    return Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: JarsColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: JarsColors.border),
                      ),
                      child: Center(
                        child: Text(
                          'No rooms yet',
                          style: GoogleFonts.inter(
                            color: JarsColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  }

                  return Column(
                    children: rooms
                        .map((room) => _RoomCard(
                              room: room,
                              isActive: activeRoom?.id == room.id,
                              onTap: () {
                                ref
                                    .read(activeRoomProvider.notifier)
                                    .setRoom(room);
                                ref.invalidate(myScoreProvider);
                                ref.invalidate(roomScoresProvider);
                                context.go('/');
                              },
                              isAdmin: room.adminId ==
                                  SupabaseService.currentUserId,
                              onAdmin: () =>
                                  _showAdminSettings(context, ref, room),
                            ))
                        .toList(),
                  );
                },
                loading: () => const Center(
                  child: CircularProgressIndicator(
                      color: JarsColors.primary),
                ),
                error: (e, _) => Text('Error: $e'),
              ),
              const SizedBox(height: 28),

              // Badges section
              _BadgesSection(),
              const SizedBox(height: 16),

              // Join / Create room button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/auth/room-entry'),
                  icon: const Icon(Icons.add),
                  label: const Text('Join or Create Room'),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  void _showSettings(BuildContext context, WidgetRef ref) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: JarsColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: JarsColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 24),
                ListTile(
                  leading: Icon(Icons.notifications_active_outlined,
                      color: JarsColors.primary.withValues(alpha: 0.9)),
                  title: Text(
                    'Test push notification',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: JarsColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Triggers your notifications webhook → Edge Function → FCM. '
                    'On web, keep this tab focused or check the system tray.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: JarsColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  onTap: () async {
                    nav.pop();
                    final uid = SupabaseService.currentUserId;
                    if (uid == null) {
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('Not signed in.')),
                      );
                      return;
                    }
                    final regOk = await NotificationService.registerToken();
                    if (!regOk) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Could not save FCM token. Allow notifications, hard refresh, '
                            'and ensure web/firebase-messaging-sw.js is deployed. Then try again.',
                            style: GoogleFonts.inter(),
                          ),
                          backgroundColor: JarsColors.red,
                        ),
                      );
                      return;
                    }
                    final ok = await NotificationService.sendNotification(
                      targetUserId: uid,
                      body:
                          'Jars test — webhook → Edge Function → FCM. Pipeline OK.',
                    );
                    if (ok) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Test sent. Check for a system notification.',
                            style: GoogleFonts.inter(),
                          ),
                        ),
                      );
                    } else {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Insert failed (RLS or network). Check Supabase logs.',
                            style: GoogleFonts.inter(),
                          ),
                          backgroundColor: JarsColors.red,
                        ),
                      );
                    }
                  },
                ),
                const Divider(height: 32),
                ListTile(
                  leading: const Icon(Icons.logout, color: JarsColors.red),
                  title: Text(
                    'Sign Out',
                    style: GoogleFonts.inter(color: JarsColors.red),
                  ),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await AuthService.signOut();
                    if (context.mounted) {
                      context.go('/auth');
                    }
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showAdminSettings(
      BuildContext context, WidgetRef ref, Room room) {
    final goalController = TextEditingController(
      text: room.dailyGoalPoints?.toString() ?? '',
    );
    final streakController = TextEditingController(
      text: room.streakMinimum.toString(),
    );
    final maxController = TextEditingController(
      text: room.maxParticipants.toString(),
    );

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarsColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
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
                const SizedBox(height: 20),
                Text(
                  'Room Settings',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: JarsColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                _SettingsField(
                  label: 'Daily Goal (pts)',
                  controller: goalController,
                ),
                const SizedBox(height: 16),
                _SettingsField(
                  label: 'Streak Minimum (pts)',
                  controller: streakController,
                ),
                const SizedBox(height: 16),
                _SettingsField(
                  label: 'Max Participants',
                  controller: maxController,
                ),
                const SizedBox(height: 24),

                // Custom exercise creation
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showCreateExercise(context, ref, room.id);
                  },
                  icon: const Icon(Icons.add),
                  label: const Text('Add Custom Exercise'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 12),

                // Group goal
                OutlinedButton.icon(
                  onPressed: () {
                    Navigator.pop(context);
                    _showGroupGoal(context, ref, room.id);
                  },
                  icon: const Icon(Icons.flag_outlined),
                  label: const Text('Set Group Goal'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                  ),
                ),
                const SizedBox(height: 16),

                // Save button
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final updates = <String, dynamic>{};
                      final goal =
                          int.tryParse(goalController.text);
                      final streak =
                          int.tryParse(streakController.text);
                      final max =
                          int.tryParse(maxController.text);

                      if (goal != null) {
                        updates['daily_goal_points'] = goal;
                        updates['daily_goal_set_at'] =
                            DateTime.now().toIso8601String();
                      }
                      if (streak != null) {
                        updates['streak_minimum'] = streak;
                      }
                      if (max != null) {
                        updates['max_participants'] = max;
                      }

                      if (updates.isNotEmpty) {
                        await RoomService.updateRoom(
                            room.id, updates);
                        ref.invalidate(userRoomsProvider);
                        ref
                            .read(activeRoomProvider.notifier)
                            .refresh();
                      }
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text('Save',
                        style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                const SizedBox(height: 12),

                // Reset room scores
                Center(
                  child: TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: JarsColors.surfaceRaised,
                          title: Text('Reset Room Scores?',
                              style: GoogleFonts.spaceGrotesk(
                                  color: JarsColors.textPrimary)),
                          content: Text(
                              'All scores, streaks, and daily points will be set to 0. This cannot be undone.',
                              style: GoogleFonts.inter(
                                  color: JarsColors.textSecondary)),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, true),
                              child: Text('Reset',
                                  style: GoogleFonts.inter(
                                      color: JarsColors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await RoomService.resetRoomScores(room.id);
                        ref.invalidate(myScoreProvider);
                        ref.invalidate(roomScoresProvider);
                      }
                    },
                    child: Text(
                      'Reset Room Scores',
                      style: GoogleFonts.inter(
                        color: JarsColors.red,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),

                // Delete room
                Center(
                  child: TextButton(
                    onPressed: () async {
                      Navigator.pop(context);
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: JarsColors.surfaceRaised,
                          title: Text('Delete Room?',
                              style: GoogleFonts.spaceGrotesk(
                                  color: JarsColors.textPrimary)),
                          content: Text(
                              'This will remove the room and all data.',
                              style: GoogleFonts.inter(
                                  color: JarsColors.textSecondary)),
                          actions: [
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            TextButton(
                              onPressed: () =>
                                  Navigator.pop(ctx, true),
                              child: Text('Delete',
                                  style: GoogleFonts.inter(
                                      color: JarsColors.red)),
                            ),
                          ],
                        ),
                      );
                      if (confirmed == true) {
                        await RoomService.deleteRoom(room.id);
                        ref.invalidate(userRoomsProvider);
                        ref
                            .read(activeRoomProvider.notifier)
                            .clear();
                      }
                    },
                    child: Text(
                      'Delete Room',
                      style: GoogleFonts.inter(
                        color: JarsColors.red,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showCreateExercise(
      BuildContext context, WidgetRef ref, String roomId) {
    final nameController = TextEditingController();
    final pointsController = TextEditingController();
    final iconController = TextEditingController(text: '💪');
    String category = 'Custom';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarsColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
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
                const SizedBox(height: 20),
                Text(
                  'Custom Exercise',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: JarsColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                _SettingsField(
                  label: 'Name',
                  controller: nameController,
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 16),
                _SettingsField(
                  label: 'Points per rep',
                  controller: pointsController,
                ),
                const SizedBox(height: 16),
                _SettingsField(
                  label: 'Icon (emoji)',
                  controller: iconController,
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      final points =
                          double.tryParse(pointsController.text);
                      if (name.isEmpty || points == null) return;

                      await ExerciseService.createCustomExercise(
                        roomId: roomId,
                        name: name,
                        points: points,
                        icon: iconController.text.trim().isEmpty
                            ? '💪'
                            : iconController.text.trim(),
                        category: category,
                      );
                      ref.invalidate(roomExercisesProvider);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Create'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showGroupGoal(
      BuildContext context, WidgetRef ref, String roomId) {
    final targetController = TextEditingController();
    final daysController = TextEditingController(text: '7');
    final descController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarsColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              24,
              24,
              24,
              MediaQuery.of(context).viewInsets.bottom + 24,
            ),
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
                const SizedBox(height: 20),
                Text(
                  'Group Goal',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: JarsColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 20),
                _SettingsField(
                  label: 'Target Points (total)',
                  controller: targetController,
                ),
                const SizedBox(height: 16),
                _SettingsField(
                  label: 'Duration (days)',
                  controller: daysController,
                ),
                const SizedBox(height: 16),
                _SettingsField(
                  label: 'Description (optional)',
                  controller: descController,
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final target =
                          int.tryParse(targetController.text);
                      final days =
                          int.tryParse(daysController.text);
                      if (target == null || days == null) return;

                      await GoalService.createGoal(
                        roomId: roomId,
                        targetPoints: target,
                        durationDays: days,
                        description: descController.text.isEmpty
                            ? null
                            : descController.text,
                      );
                      ref.invalidate(groupGoalProvider);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: const Text('Set Goal'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RoomCard extends StatelessWidget {
  final Room room;
  final bool isActive;
  final VoidCallback onTap;
  final bool isAdmin;
  final VoidCallback? onAdmin;

  const _RoomCard({
    required this.room,
    required this.isActive,
    required this.onTap,
    this.isAdmin = false,
    this.onAdmin,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: JarsColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isActive ? JarsColors.primary : JarsColors.border,
              width: isActive ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          room.name,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: JarsColors.primaryDim,
                              borderRadius: BorderRadius.circular(9999),
                            ),
                            child: Text(
                              'Active',
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: JarsColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Code: ${room.roomCode}',
                      style: GoogleFonts.spaceMono(
                        fontSize: 11,
                        color: JarsColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAdmin)
                IconButton(
                  onPressed: onAdmin,
                  icon: const Icon(Icons.settings_outlined,
                      size: 20, color: JarsColors.textSecondary),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String icon;
  final String label;
  final String value;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: JarsColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: JarsColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(icon, style: const TextStyle(fontSize: 20)),
            const SizedBox(height: 8),
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: JarsColors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GoogleFonts.spaceMono(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: JarsColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BadgesSection extends StatefulWidget {
  @override
  State<_BadgesSection> createState() => _BadgesSectionState();
}

class _BadgesSectionState extends State<_BadgesSection> {
  List<AppBadge> _badges = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    BadgeService.getMyBadges().then((b) {
      if (mounted) setState(() { _badges = b; _loading = false; });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Badges',
          style: GoogleFonts.spaceGrotesk(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: JarsColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const SizedBox(height: 40)
        else if (_badges.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: JarsColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: JarsColors.border),
            ),
            child: Text(
              'No badges yet — keep competing!',
              style: GoogleFonts.inter(
                color: JarsColors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _badges.map((b) => _BadgeChip(badge: b)).toList(),
          ),
      ],
    );
  }
}

class _BadgeChip extends StatelessWidget {
  final AppBadge badge;
  const _BadgeChip({required this.badge});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: badge.displayLabel +
          (badge.displayRank != null ? ' · Rank #${badge.displayRank}' : ''),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: JarsColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: JarsColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(badge.displayEmoji, style: const TextStyle(fontSize: 18)),
            const SizedBox(width: 6),
            Text(
              badge.displayLabel,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: JarsColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _SettingsField({
    required this.label,
    required this.controller,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType ?? TextInputType.number,
      style: GoogleFonts.inter(
        fontSize: 16,
        color: JarsColors.textPrimary,
      ),
      cursorColor: JarsColors.primary,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(
          fontSize: 14,
          color: JarsColors.textSecondary,
        ),
        filled: true,
        fillColor: JarsColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JarsColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JarsColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: JarsColors.primary),
        ),
      ),
    );
  }
}
