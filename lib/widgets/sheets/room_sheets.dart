import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../ui/member_avatar_ring.dart';
import '../../models/room.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/feed_provider.dart';
import '../../providers/goal_provider.dart';
import '../../providers/room_provider.dart';
import '../../providers/score_provider.dart';
import '../../services/event_service.dart';
import '../../services/room_service.dart';
import '../../services/supabase_service.dart';

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 6),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: JarsColors.border,
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }
}

class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

/// Modal bottom sheet: enter 6-character room code (InvoiceFly-style draggable sheet).
Future<void> showJoinRoomSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => const _JoinRoomSheet(),
  );
}

class _JoinRoomSheet extends ConsumerStatefulWidget {
  const _JoinRoomSheet();

  @override
  ConsumerState<_JoinRoomSheet> createState() => _JoinRoomSheetState();
}

class _JoinRoomSheetState extends ConsumerState<_JoinRoomSheet> {
  final _code = TextEditingController();
  final _password = TextEditingController();
  bool _loading = false;
  Room? _preview;

  @override
  void dispose() {
    _code.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.length < 6) return;
    setState(() => _loading = true);
    try {
      final pw = _password.text.trim();
      final room = await RoomService.joinByCode(
        code,
        password: pw.isEmpty ? null : pw,
      );
      if (!mounted) return;
      if (room != null) {
        ref.read(activeRoomProvider.notifier).setRoom(room);
        ref.invalidate(userRoomsProvider);
        ref.invalidate(roomFeedWithReactionsProvider);
        ref.invalidate(roomFeedProvider);
        Navigator.of(context).pop();
        context.go('/');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room not found or full')),
        );
      }
    } on InvalidRoomPasswordException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Wrong room password')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.52,
        minChildSize: 0.38,
        maxChildSize: 0.88,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: JarsColors.surfaceRaised,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: JarsColors.border, width: 0.5),
              ),
            ),
            child: Column(
              children: [
                const _SheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: JarsColors.textSecondary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          'Join a room',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                    children: [
                      Text(
                        'Ask your crew for their 6-character code.',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: JarsColors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 24),
                      TextField(
                        controller: _code,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.characters,
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(
                            RegExp(r'[A-Za-z0-9]'),
                          ),
                          _UpperCaseFormatter(),
                        ],
                        style: GoogleFonts.spaceMono(
                          fontSize: 36,
                          fontWeight: FontWeight.w700,
                          color: JarsColors.textPrimary,
                          letterSpacing: 14,
                        ),
                        cursorColor: JarsColors.primary,
                        decoration: InputDecoration(
                          hintText: '------',
                          hintStyle: GoogleFonts.spaceMono(
                            fontSize: 36,
                            color: JarsColors.textTertiary,
                            letterSpacing: 14,
                          ),
                          counterText: '',
                          filled: true,
                          fillColor: JarsColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(color: JarsColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: const BorderSide(
                              color: JarsColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        onChanged: (v) async {
                          setState(() {});
                          if (v.length < 6) {
                            setState(() => _preview = null);
                            return;
                          }
                          final r = await RoomService.peekRoomByCode(v);
                          if (!mounted) return;
                          setState(() => _preview = r);
                          if (r != null && !r.requiresJoinPassword) {
                            _join();
                          }
                        },
                      ),
                      if (_preview != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _preview!.name,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                      ],
                      if (_preview?.requiresJoinPassword == true) ...[
                        const SizedBox(height: 16),
                        TextField(
                          controller: _password,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Room password',
                            hintText: 'Required for this room',
                            filled: true,
                            fillColor: JarsColors.background,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 28),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: (_code.text.trim().length == 6 &&
                                  !_loading)
                              ? _join
                              : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: JarsColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: JarsColors.surface,
                            disabledForegroundColor: JarsColors.textTertiary,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Join',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Modal bottom sheet: name + max members, then create.
Future<void> showCreateRoomSheet(BuildContext context) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => const _CreateRoomSheet(),
  );
}

class _CreateRoomSheet extends ConsumerStatefulWidget {
  const _CreateRoomSheet();

  @override
  ConsumerState<_CreateRoomSheet> createState() => _CreateRoomSheetState();
}

class _CreateRoomSheetState extends ConsumerState<_CreateRoomSheet> {
  final _name = TextEditingController();
  double _maxMembers = 10;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  bool get _canSubmit =>
      _name.text.trim().isNotEmpty && !_loading;

  Future<void> _create() async {
    final n = _name.text.trim();
    if (n.isEmpty) return;
    setState(() => _loading = true);
    try {
      final room = await RoomService.createRoom(
        name: n,
        maxParticipants: _maxMembers.round(),
      );
      if (!mounted) return;
      ref.read(activeRoomProvider.notifier).setRoom(room);
      ref.invalidate(userRoomsProvider);
      Navigator.of(context).pop();
      context.go('/');
    } catch (e, st) {
      developer.log('Create room failed', error: e, stackTrace: st);
      if (kDebugMode) {
        debugPrint('Create room failed: $e');
        debugPrintStack(stackTrace: st);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is StateError ? e.message : '$e',
              style: const TextStyle(fontSize: 13),
            ),
            duration: const Duration(seconds: 8),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.58,
        minChildSize: 0.42,
        maxChildSize: 0.9,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: JarsColors.surfaceRaised,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              border: Border(
                top: BorderSide(color: JarsColors.border, width: 0.5),
              ),
            ),
            child: Column(
              children: [
                const _SheetHandle(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: JarsColors.textSecondary,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          'Create a room',
                          textAlign: TextAlign.center,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: JarsColors.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                    children: [
                      TextField(
                        controller: _name,
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: JarsColors.textPrimary,
                        ),
                        cursorColor: JarsColors.primary,
                        textCapitalization: TextCapitalization.words,
                        decoration: InputDecoration(
                          labelText: 'Room name',
                          hintText: 'e.g. Morning lifters',
                          labelStyle: GoogleFonts.inter(
                            color: JarsColors.textSecondary,
                          ),
                          filled: true,
                          fillColor: JarsColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: JarsColors.border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(
                              color: JarsColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Max members',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: JarsColors.textSecondary,
                            ),
                          ),
                          Text(
                            '${_maxMembers.round()}',
                            style: GoogleFonts.spaceMono(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: JarsColors.primary,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: _maxMembers,
                        min: 2,
                        max: 20,
                        divisions: 18,
                        activeColor: JarsColors.primary,
                        inactiveColor: JarsColors.border,
                        onChanged: (v) => setState(() => _maxMembers = v),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: FilledButton(
                          onPressed: _canSubmit ? _create : null,
                          style: FilledButton.styleFrom(
                            backgroundColor: JarsColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: JarsColors.surface,
                            disabledForegroundColor: JarsColors.textTertiary,
                          ),
                          child: _loading
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
                                  'Create room',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Admin: room member list (kick / reset)
// ─────────────────────────────────────────────────────────────────────────────

void _invalidateRoomLists(WidgetRef ref, String roomId) {
  ref.invalidate(roomMembersProvider(roomId));
  ref.invalidate(roomScoresProvider);
  ref.invalidate(myScoreProvider);
  ref.invalidate(groupGoalProgressProvider);
  ref.invalidate(roomFeedProvider);
  ref.invalidate(roomFeedWithReactionsProvider);
}

Future<void> showRoomMembersAdminSheet(
  BuildContext context,
  WidgetRef ref,
  Room room,
) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JarsColors.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetCtx) {
      final maxH = MediaQuery.sizeOf(sheetCtx).height * 0.62;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
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
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Members',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: JarsColors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    color: JarsColors.textSecondary,
                    onPressed: () => Navigator.pop(sheetCtx),
                  ),
                ],
              ),
              Text(
                'Remove from room or reset their logs & points.',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: JarsColors.textSecondary,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: maxH,
                child: Consumer(
                  builder: (_, cref, __) {
                    final async = cref.watch(roomMembersProvider(room.id));
                    return async.when(
                      data: (members) {
                        if (members.isEmpty) {
                          return Center(
                            child: Text(
                              'No members',
                              style: GoogleFonts.inter(
                                color: JarsColors.textTertiary,
                              ),
                            ),
                          );
                        }
                        return ListView.separated(
                          itemCount: members.length,
                          separatorBuilder: (_, __) =>
                              const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final m = members[i];
                            final userId = m['user_id'] as String;
                            final profiles = m['profiles'];
                            final username = profiles is Map
                                ? (profiles['username'] as String? ??
                                    userId.substring(0, 8))
                                : userId.substring(0, 8);
                            final me = SupabaseService.currentUserId;
                            final isSelf = me == userId;
                            final isRoomAdmin = userId == room.adminId;

                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: MemberAvatarCircle(
                                initial: username.isNotEmpty
                                    ? username.substring(0, 1)
                                    : '?',
                                color: memberColorForIndex(i),
                                size: 40,
                                showBorder: false,
                              ),
                              title: Text(
                                username,
                                style: GoogleFonts.spaceGrotesk(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 15,
                                  color: JarsColors.textPrimary,
                                ),
                              ),
                              subtitle: Text(
                                isRoomAdmin
                                    ? 'Admin'
                                    : (isSelf ? 'You' : 'Member'),
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: JarsColors.textTertiary,
                                ),
                              ),
                              trailing: (isSelf || isRoomAdmin)
                                  ? null
                                  : Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TextButton(
                                          onPressed: () async {
                                            final ok =
                                                await showDialog<bool>(
                                              context: sheetCtx,
                                              builder: (dCtx) =>
                                                  AlertDialog(
                                                backgroundColor:
                                                    JarsColors
                                                        .surfaceRaised,
                                                title: Text(
                                                  'Reset $username?',
                                                  style: GoogleFonts
                                                      .spaceGrotesk(
                                                    color: JarsColors
                                                        .textPrimary,
                                                  ),
                                                ),
                                                content: Text(
                                                  'Deletes their workout logs in this room and sets their score to 0.',
                                                  style:
                                                      GoogleFonts.inter(
                                                    color: JarsColors
                                                        .textSecondary,
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            dCtx, false),
                                                    child: const Text(
                                                        'Cancel'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            dCtx, true),
                                                    child: Text(
                                                      'Reset',
                                                      style: GoogleFonts
                                                          .inter(
                                                        color: JarsColors
                                                            .gold,
                                                        fontWeight:
                                                            FontWeight
                                                                .w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok != true ||
                                                !sheetCtx.mounted) {
                                              return;
                                            }
                                            try {
                                              await RoomService
                                                  .adminResetRoomMember(
                                                room.id,
                                                userId,
                                              );
                                              _invalidateRoomLists(
                                                  cref, room.id);
                                              if (sheetCtx.mounted) {
                                                ScaffoldMessenger.of(
                                                        sheetCtx)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      '$username reset',
                                                      style:
                                                          GoogleFonts
                                                              .inter(),
                                                    ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              if (sheetCtx.mounted) {
                                                ScaffoldMessenger.of(
                                                        sheetCtx)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        'Reset failed: $e'),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          child: Text(
                                            'Reset',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: JarsColors.gold,
                                            ),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: () async {
                                            final ok =
                                                await showDialog<bool>(
                                              context: sheetCtx,
                                              builder: (dCtx) =>
                                                  AlertDialog(
                                                backgroundColor:
                                                    JarsColors
                                                        .surfaceRaised,
                                                title: Text(
                                                  'Remove $username?',
                                                  style: GoogleFonts
                                                      .spaceGrotesk(
                                                    color: JarsColors
                                                        .textPrimary,
                                                  ),
                                                ),
                                                content: Text(
                                                  'They can re-join with the room code if you allow it.',
                                                  style:
                                                      GoogleFonts.inter(
                                                    color: JarsColors
                                                        .textSecondary,
                                                  ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            dCtx, false),
                                                    child: const Text(
                                                        'Cancel'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            dCtx, true),
                                                    child: Text(
                                                      'Remove',
                                                      style: GoogleFonts
                                                          .inter(
                                                        color: JarsColors
                                                            .red,
                                                        fontWeight:
                                                            FontWeight
                                                                .w600,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok != true ||
                                                !sheetCtx.mounted) {
                                              return;
                                            }
                                            try {
                                              await EventService
                                                  .roomMemberKicked(
                                                roomId: room.id,
                                                removedUserId: userId,
                                                removedUsername: username,
                                                roomName: room.name,
                                              );
                                              await RoomService.kickMember(
                                                room.id,
                                                userId,
                                              );
                                              _invalidateRoomLists(
                                                  cref, room.id);
                                              cref.invalidate(
                                                  roomFeedWithReactionsProvider);
                                              cref.invalidate(
                                                  roomFeedProvider);
                                              if (sheetCtx.mounted) {
                                                ScaffoldMessenger.of(
                                                        sheetCtx)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                      '$username removed',
                                                      style:
                                                          GoogleFonts
                                                              .inter(),
                                                    ),
                                                  ),
                                                );
                                              }
                                            } catch (e) {
                                              if (sheetCtx.mounted) {
                                                ScaffoldMessenger.of(
                                                        sheetCtx)
                                                    .showSnackBar(
                                                  SnackBar(
                                                    content: Text(
                                                        'Remove failed: $e'),
                                                  ),
                                                );
                                              }
                                            }
                                          },
                                          child: Text(
                                            'Remove',
                                            style: GoogleFonts.inter(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w600,
                                              color: JarsColors.red,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                            );
                          },
                        );
                      },
                      loading: () => const Center(
                        child: CircularProgressIndicator(
                          color: JarsColors.primary,
                        ),
                      ),
                      error: (e, _) => Center(
                        child: Text(
                          'Error: $e',
                          style: GoogleFonts.inter(
                            color: JarsColors.textSecondary,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}
