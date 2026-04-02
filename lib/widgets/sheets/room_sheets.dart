import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../providers/active_room_provider.dart';
import '../../providers/room_provider.dart';
import '../../services/room_service.dart';

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
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _code.text.trim();
    if (code.length < 6) return;
    setState(() => _loading = true);
    try {
      final room = await RoomService.joinByCode(code);
      if (!mounted) return;
      if (room != null) {
        ref.read(activeRoomProvider.notifier).setRoom(room);
        ref.invalidate(userRoomsProvider);
        Navigator.of(context).pop();
        context.go('/');
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Room not found or full')),
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
                        onChanged: (v) {
                          setState(() {});
                          if (v.length == 6) _join();
                        },
                      ),
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
