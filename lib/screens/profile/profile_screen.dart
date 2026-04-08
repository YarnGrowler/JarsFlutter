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
import '../../providers/feed_provider.dart';
import '../../services/log_service.dart';
import '../../services/room_service.dart';
import '../../services/notification_service.dart';
import '../../services/supabase_service.dart';
import '../../models/badge.dart';
import '../../providers/exercise_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/profile_provider.dart';
import '../../widgets/sheets/create_custom_exercise_sheet.dart';
import '../../widgets/sheets/group_goal_sheet.dart';
import '../../providers/ui_text_scale_provider.dart';
import '../../core/user_display_name.dart';
import '../../widgets/ui/rank_badge.dart';
import 'notification_settings_screen.dart';

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
        return Consumer(
          builder: (context, ref, _) {
            final textScale = ref.watch(uiTextScaleProvider);
            return SafeArea(
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
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
                  leading: Icon(Icons.notifications_outlined,
                      color: JarsColors.primary.withValues(alpha: 0.9)),
                  title: Text(
                    'Push notifications & devices',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w600,
                      color: JarsColors.textPrimary,
                    ),
                  ),
                  subtitle: Text(
                    'Request permission (iPhone Home Screen), see registered devices, revoke old ones.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: JarsColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  onTap: () {
                    nav.pop();
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NotificationSettingsScreen(),
                      ),
                    );
                  },
                ),
                const Divider(height: 24),
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
                    final uid = SupabaseService.currentUserId;
                    if (uid == null) {
                      nav.pop();
                      scaffoldMessenger.showSnackBar(
                        const SnackBar(content: Text('Not signed in.')),
                      );
                      return;
                    }
                    // Register before closing the sheet so iOS WebKit still ties
                    // requestPermission to this tap (no pop / await before it).
                    final regOk = await NotificationService.registerToken();
                    nav.pop();
                    if (!regOk) {
                      scaffoldMessenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            'Could not save FCM token. On iPhone (Home Screen app), '
                            'open Profile → Push notifications & devices and tap Enable there. '
                            'Otherwise allow notifications and ensure firebase-messaging-sw.js is deployed.',
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
                const Divider(height: 28),
                Text(
                  'Text size',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: JarsColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Saved on this device only.',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: JarsColors.textSecondary,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Text(
                      'A',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: JarsColors.textTertiary,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: textScale,
                        min: 0.85,
                        max: 1.3,
                        divisions: 9,
                        label: '${(textScale * 100).round()}%',
                        onChanged: (v) =>
                            ref.read(uiTextScaleProvider.notifier).setScale(v),
                      ),
                    ),
                    Text(
                      'A',
                      style: GoogleFonts.inter(
                        fontSize: 18,
                        color: JarsColors.textTertiary,
                      ),
                    ),
                  ],
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
              ),
            );
          },
        );
      },
    );
  }

  void _showAdminSettings(
      BuildContext context, WidgetRef ref, Room room) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarsColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => _AdminRoomSettingsSheet(
        room: room,
        dialogContext: context,
        onCreateExercise: () {
          Navigator.pop(sheetCtx);
          _showCreateExercise(context, ref, room.id);
        },
      ),
    );
  }

  void _showCreateExercise(
      BuildContext context, WidgetRef ref, String roomId) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarsColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => CreateCustomExerciseSheet(roomId: roomId),
    );
  }

}

class _AdminRoomSettingsSheet extends ConsumerStatefulWidget {
  final Room room;
  final BuildContext dialogContext;
  final VoidCallback onCreateExercise;

  const _AdminRoomSettingsSheet({
    required this.room,
    required this.dialogContext,
    required this.onCreateExercise,
  });

  @override
  ConsumerState<_AdminRoomSettingsSheet> createState() =>
      _AdminRoomSettingsSheetState();
}

class _AdminRoomSettingsSheetState
    extends ConsumerState<_AdminRoomSettingsSheet> {
  late final TextEditingController nameController;

  bool _joinPasswordRequired = false;

  Future<void> _refreshJoinPasswordFlag() async {
    final v = await RoomService.getJoinPasswordRequired(widget.room.id);
    if (mounted) setState(() => _joinPasswordRequired = v);
  }

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    _joinPasswordRequired = room.requiresJoinPassword;
    RoomService.getJoinPasswordRequired(room.id).then((required) {
      if (!mounted) return;
      setState(() => _joinPasswordRequired = required);
    });
    nameController = TextEditingController(text: room.name);
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  Future<void> _openJoinPasswordSheet() async {
    final room = widget.room;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: JarsColors.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _RoomJoinPasswordSheet(
        roomId: room.id,
        joinPasswordOn: _joinPasswordRequired,
        onChanged: () async {
          await _refreshJoinPasswordFlag();
          ref.invalidate(userRoomsProvider);
          ref.read(activeRoomProvider.notifier).refresh();
        },
      ),
    );
    await _refreshJoinPasswordFlag();
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          12,
          24,
          bottomInset > 0 ? bottomInset + 16 : 24,
        ),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.52,
          ),
          child: SingleChildScrollView(
            keyboardDismissBehavior:
                ScrollViewKeyboardDismissBehavior.onDrag,
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
              const SizedBox(height: 16),
              Text(
                'Room Settings',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: JarsColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
                      _SettingsField(
                        label: 'Room name',
                        controller: nameController,
                        keyboardType: TextInputType.text,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Icon(
                            _joinPasswordRequired
                                ? Icons.lock_outline_rounded
                                : Icons.lock_open_rounded,
                            size: 18,
                            color: JarsColors.textSecondary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Join password',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: JarsColors.textSecondary,
                                  ),
                                ),
                                Text(
                                  _joinPasswordRequired
                                      ? 'On — required for new members'
                                      : 'Off — room code only',
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    color: JarsColors.textPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _openJoinPasswordSheet,
                            child: const Text('Change'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      OutlinedButton(
                        onPressed: () {
                          showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: JarsColors.surfaceRaised,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(20)),
                            ),
                            builder: (ctx) => _RoomCustomizationSheet(
                              room: room,
                              onCreateExercise: () {
                                Navigator.pop(ctx);
                                widget.onCreateExercise();
                              },
                            ),
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: JarsColors.textPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          side: const BorderSide(color: JarsColors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.tune_rounded,
                                color: JarsColors.primary),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Customization',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: JarsColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Wake card, goals, exercises',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: JarsColors.textTertiary,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: JarsColors.textTertiary),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () {
                          final root = widget.dialogContext;
                          Navigator.pop(context);
                          showGroupGoalSheet(root, room.id);
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: JarsColors.textPrimary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 14),
                          side: const BorderSide(color: JarsColors.border),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.flag_outlined, color: JarsColors.green),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Group goal',
                                    style: GoogleFonts.spaceGrotesk(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: JarsColors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Set a room-wide points target',
                                    style: GoogleFonts.inter(
                                      fontSize: 12,
                                      color: JarsColors.textTertiary,
                                      height: 1.3,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.chevron_right_rounded,
                                color: JarsColors.textTertiary),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            final name = nameController.text.trim();
                            if (name.isNotEmpty) {
                              await RoomService.updateRoom(room.id, {
                                'name': name,
                              });
                            }
                            ref.invalidate(userRoomsProvider);
                            ref.invalidate(groupGoalProgressProvider);
                            ref.read(activeRoomProvider.notifier).refresh();
                            if (context.mounted) Navigator.pop(context);
                          },
                          child: Text(
                            'Save',
                            style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: TextButton(
                          onPressed: () async {
                            final parent = widget.dialogContext;
                            final confirmed = await showDialog<bool>(
                              context: parent,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: JarsColors.surfaceRaised,
                                title: Text(
                                  'Reset Room Scores?',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: JarsColors.textPrimary,
                                  ),
                                ),
                                content: Text(
                                  'All scores, streaks, and daily points will be set to 0. This cannot be undone.',
                                  style: GoogleFonts.inter(
                                    color: JarsColors.textSecondary,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(
                                      'Reset',
                                      style: GoogleFonts.inter(
                                          color: JarsColors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (!mounted) return;
                            if (confirmed == true) {
                              await RoomService.resetRoomScores(room.id);
                              if (!parent.mounted) return;
                              ref.invalidate(myScoreProvider);
                              ref.invalidate(roomScoresProvider);
                              ref.invalidate(groupGoalProgressProvider);
                              if (mounted) Navigator.pop(context);
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
                      Center(
                        child: TextButton(
                          onPressed: () async {
                            final parent = widget.dialogContext;
                            final confirmed = await showDialog<bool>(
                              context: parent,
                              builder: (ctx) => AlertDialog(
                                backgroundColor: JarsColors.surfaceRaised,
                                title: Text(
                                  'Delete Room?',
                                  style: GoogleFonts.spaceGrotesk(
                                    color: JarsColors.textPrimary,
                                  ),
                                ),
                                content: Text(
                                  'This will remove the room and all data.',
                                  style: GoogleFonts.inter(
                                    color: JarsColors.textSecondary,
                                  ),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, false),
                                    child: const Text('Cancel'),
                                  ),
                                  TextButton(
                                    onPressed: () => Navigator.pop(ctx, true),
                                    child: Text(
                                      'Delete',
                                      style: GoogleFonts.inter(
                                          color: JarsColors.red),
                                    ),
                                  ),
                                ],
                              ),
                            );
                            if (!mounted) return;
                            if (confirmed == true) {
                              await RoomService.deleteRoom(room.id);
                              if (!parent.mounted) return;
                              ref.invalidate(userRoomsProvider);
                              ref.read(activeRoomProvider.notifier).clear();
                              if (mounted) Navigator.pop(context);
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
        ),
      ),
    );
  }
}

class _RoomCustomizationSheet extends ConsumerStatefulWidget {
  final Room room;
  final VoidCallback onCreateExercise;

  const _RoomCustomizationSheet({
    required this.room,
    required this.onCreateExercise,
  });

  @override
  ConsumerState<_RoomCustomizationSheet> createState() =>
      _RoomCustomizationSheetState();
}

class _RoomCustomizationSheetState
    extends ConsumerState<_RoomCustomizationSheet> {
  late final TextEditingController idleNudgeController;
  late final TextEditingController goalController;
  late final TextEditingController streakController;
  late final TextEditingController maxController;
  bool _wakeBusy = false;

  @override
  void initState() {
    super.initState();
    final room = widget.room;
    idleNudgeController =
        TextEditingController(text: room.idleNudgeHours.toString());
    goalController = TextEditingController(
      text: room.dailyGoalPoints?.toString() ?? '',
    );
    streakController =
        TextEditingController(text: room.streakMinimum.toString());
    maxController =
        TextEditingController(text: room.maxParticipants.toString());
  }

  @override
  void dispose() {
    idleNudgeController.dispose();
    goalController.dispose();
    streakController.dispose();
    maxController.dispose();
    super.dispose();
  }

  Future<void> _postWakeReminderNow() async {
    if (_wakeBusy) return;
    final room = widget.room;
    setState(() => _wakeBusy = true);
    try {
      final rows = await RoomService.getRoomMembers(room.id);
      if (!mounted) return;
      final choices = <({String id, String name})>[];
      for (final r in rows) {
        final id = r['user_id'] as String?;
        if (id == null) continue;
        final p = r['profiles'];
        var name = 'Member';
        if (p is Map && p['username'] is String) {
          name = p['username'] as String;
        }
        choices.add((id: id, name: name));
      }
      choices.sort(
        (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
      );
      final picked = await showModalBottomSheet<({String id, String name})>(
        context: context,
        backgroundColor: JarsColors.surfaceRaised,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                  child: Text(
                    'Post wake card for…',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: JarsColors.textPrimary,
                    ),
                  ),
                ),
                for (final c in choices)
                  ListTile(
                    title: Text(
                      c.name,
                      style: GoogleFonts.inter(
                        color: JarsColors.textPrimary,
                      ),
                    ),
                    onTap: () => Navigator.pop(ctx, c),
                  ),
              ],
            ),
          ),
        ),
      );
      if (picked == null || !mounted) return;
      await LogService.adminPostWakeReminder(
        roomId: room.id,
        targetUserId: picked.id,
      );
      ref.invalidate(roomFeedWithReactionsProvider);
      ref.invalidate(roomFeedProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Wake card posted for ${picked.name}',
            style: GoogleFonts.inter(),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      var msg = e.toString();
      if (msg.contains('wake_recently_posted')) {
        msg =
            'A wake card for that member was already posted in the last hour.';
      } else if (msg.contains('target_has_no_workout_logs')) {
        msg =
            'That member has no workout logs yet — idle wake only applies after their first log.';
      } else if (msg.contains('not_room_admin')) {
        msg = 'Only the room admin can post this.';
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg)),
      );
    } finally {
      if (mounted) setState(() => _wakeBusy = false);
    }
  }

  Future<void> _save() async {
    final room = widget.room;
    final updates = <String, dynamic>{};
    final idle = int.tryParse(idleNudgeController.text.trim());
    if (idle != null && idle >= 0 && idle <= 8760) {
      updates['idle_nudge_hours'] = idle;
    }
    final goal = int.tryParse(goalController.text);
    final streak = int.tryParse(streakController.text);
    final max = int.tryParse(maxController.text);
    if (goal != null) {
      updates['daily_goal_points'] = goal;
      updates['daily_goal_set_at'] = DateTime.now().toIso8601String();
    }
    if (streak != null) {
      updates['streak_minimum'] = streak;
    }
    if (max != null) {
      updates['max_participants'] = max;
    }
    if (updates.isNotEmpty) {
      await RoomService.updateRoom(room.id, updates);
    }
    ref.invalidate(userRoomsProvider);
    ref.invalidate(groupGoalProgressProvider);
    ref.read(activeRoomProvider.notifier).refresh();
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 12, 24, bottom + 24),
        child: SingleChildScrollView(
          child: Column(
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
              const SizedBox(height: 16),
              Text(
                'Customization',
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: JarsColors.textPrimary,
                ),
              ),
              const SizedBox(height: 20),
              _SettingsField(
                label: 'Wake card after (hours idle, 0 = off)',
                controller: idleNudgeController,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 8),
              Text(
                'While someone is past this idle time with no real workout log, the server can add a wake card about once every 20 hours (not strictly once per calendar day). New wake cards notify everyone in the room except that person so they can open the feed. Each member can send at most two wake pings per card.',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: JarsColors.textTertiary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _wakeBusy ? null : _postWakeReminderNow,
                icon: _wakeBusy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: JarsColors.primary,
                        ),
                      )
                    : const Icon(Icons.notifications_active_outlined, size: 20),
                label: Text(
                  'Post wake reminder now',
                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                  foregroundColor: JarsColors.textPrimary,
                  side: const BorderSide(color: JarsColors.border),
                ),
              ),
              const SizedBox(height: 16),
              _SettingsField(
                label: 'Daily Goal (pts)',
                controller: goalController,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _SettingsField(
                label: 'Streak Minimum (pts)',
                controller: streakController,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _SettingsField(
                label: 'Max Participants',
                controller: maxController,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: widget.onCreateExercise,
                icon: const Icon(Icons.add),
                label: const Text('Add Custom Exercise'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(double.infinity, 48),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _save,
                  child: Text(
                    'Save',
                    style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
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

/// Stacked above the room settings sheet — set / change / remove join password.
class _RoomJoinPasswordSheet extends StatefulWidget {
  final String roomId;
  final bool joinPasswordOn;
  final Future<void> Function() onChanged;

  const _RoomJoinPasswordSheet({
    required this.roomId,
    required this.joinPasswordOn,
    required this.onChanged,
  });

  @override
  State<_RoomJoinPasswordSheet> createState() =>
      _RoomJoinPasswordSheetState();
}

class _RoomJoinPasswordSheetState extends State<_RoomJoinPasswordSheet> {
  late final TextEditingController _pw;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _pw = TextEditingController();
  }

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _saveNewPassword() async {
    final t = _pw.text.trim();
    if (t.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a password to save')),
      );
      return;
    }
    setState(() => _busy = true);
    try {
      await RoomService.setRoomJoinPassword(widget.roomId, t);
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removePassword() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JarsColors.surfaceRaised,
        title: Text(
          'Remove password?',
          style: GoogleFonts.spaceGrotesk(color: JarsColors.textPrimary),
        ),
        content: Text(
          'Anyone with the room code will be able to join.',
          style: GoogleFonts.inter(color: JarsColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove',
                style: GoogleFonts.inter(color: JarsColors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      await RoomService.setRoomJoinPassword(widget.roomId, null);
      await widget.onChanged();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not remove: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(24, 16, 24, bottom + 24),
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
          const SizedBox(height: 16),
          Text(
            'Room join password',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: JarsColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.joinPasswordOn
                ? 'Enter a new password to replace the current one.'
                : 'Set a password newcomers must enter after the room code.',
            style: GoogleFonts.inter(
              fontSize: 13,
              color: JarsColors.textSecondary,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _pw,
            obscureText: true,
            decoration: InputDecoration(
              hintText: 'Password',
              filled: true,
              fillColor: JarsColors.background,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _busy ? null : _saveNewPassword,
              child: Text(
                widget.joinPasswordOn
                    ? 'Update password'
                    : 'Turn on password',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (widget.joinPasswordOn) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: OutlinedButton(
                onPressed: _busy ? null : _removePassword,
                child: Text(
                  'Turn off password',
                  style: GoogleFonts.spaceGrotesk(
                    fontWeight: FontWeight.w600,
                    color: JarsColors.red,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
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
      keyboardType: keyboardType ?? TextInputType.text,
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
