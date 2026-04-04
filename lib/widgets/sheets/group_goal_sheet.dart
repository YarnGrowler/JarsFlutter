import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../models/group_goal.dart';
import '../../providers/goal_provider.dart';
import '../../services/goal_service.dart';

/// Admin: view / end / set room group goal.
void showGroupGoalSheet(BuildContext context, String roomId) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JarsColors.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => _GroupGoalSheetBody(roomId: roomId),
  );
}

class _GroupGoalSheetBody extends ConsumerStatefulWidget {
  final String roomId;

  const _GroupGoalSheetBody({required this.roomId});

  @override
  ConsumerState<_GroupGoalSheetBody> createState() =>
      _GroupGoalSheetBodyState();
}

class _GroupGoalSheetBodyState extends ConsumerState<_GroupGoalSheetBody> {
  late final TextEditingController _targetController;
  late final TextEditingController _daysController;
  late final TextEditingController _descController;
  String? _initializedForGoalId;

  @override
  void initState() {
    super.initState();
    _targetController = TextEditingController();
    _daysController = TextEditingController(text: '7');
    _descController = TextEditingController();
  }

  @override
  void dispose() {
    _targetController.dispose();
    _daysController.dispose();
    _descController.dispose();
    super.dispose();
  }

  void _applyGoalToFields(GroupGoal? g) {
    final id = g?.id;
    if (id == _initializedForGoalId) return;
    _initializedForGoalId = id;
    if (g == null) {
      _targetController.clear();
      _daysController.text = '7';
      _descController.clear();
    } else {
      _targetController.text = '${g.targetPoints}';
      _daysController.text = '${g.durationDays}';
      _descController.text = g.description ?? '';
    }
  }

  Future<void> _confirmAndEndGoal(GroupGoal goal) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: JarsColors.surfaceRaised,
        title: Text(
          'End group goal?',
          style: GoogleFonts.spaceGrotesk(color: JarsColors.textPrimary),
        ),
        content: Text(
          'Everyone will stop tracking this goal. You can set a new one below.',
          style: GoogleFonts.inter(
            color: JarsColors.textSecondary,
            height: 1.35,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep goal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'End goal',
              style: GoogleFonts.inter(
                color: JarsColors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await GoalService.deleteGoal(goal.id);
      ref.invalidate(groupGoalProvider);
      ref.invalidate(groupGoalProgressProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Group goal ended.',
              style: GoogleFonts.inter(),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not end goal: $e'),
            backgroundColor: JarsColors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(groupGoalProgressProvider);

    return async.when(
      loading: () => const SafeArea(
        child: Padding(
          padding: EdgeInsets.all(32),
          child: Center(
            child: CircularProgressIndicator(color: JarsColors.primary),
          ),
        ),
      ),
      error: (_, __) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Could not load group goal.',
            style: GoogleFonts.inter(color: JarsColors.textSecondary),
          ),
        ),
      ),
      data: (progress) {
        _applyGoalToFields(progress?.goal);
        final bottom = MediaQuery.of(context).viewInsets.bottom;

        return SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(24, 24, 24, bottom + 24),
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
                if (progress != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    '${progress.earnedRounded} / ${progress.goal.targetPoints} pts · '
                    '${progress.pointsRemaining} to go · '
                    '${progress.goal.daysRemaining} days left',
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: JarsColors.textSecondary,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => _confirmAndEndGoal(progress.goal),
                      style: TextButton.styleFrom(
                        foregroundColor: JarsColors.red,
                      ),
                      child: Text(
                        'End group goal',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Divider(color: JarsColors.border.withValues(alpha: 0.6)),
                  const SizedBox(height: 8),
                  Text(
                    'Set or replace goal',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: JarsColors.textTertiary,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                _GroupGoalField(
                  label: 'Target Points (total)',
                  controller: _targetController,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                _GroupGoalField(
                  label: 'Duration (days)',
                  controller: _daysController,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                _GroupGoalField(
                  label: 'Description (optional)',
                  controller: _descController,
                  keyboardType: TextInputType.text,
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () async {
                      final target = int.tryParse(_targetController.text);
                      final days = int.tryParse(_daysController.text);
                      if (target == null || days == null) return;

                      await GoalService.createGoal(
                        roomId: widget.roomId,
                        targetPoints: target,
                        durationDays: days,
                        description: _descController.text.isEmpty
                            ? null
                            : _descController.text,
                      );
                      ref.invalidate(groupGoalProvider);
                      ref.invalidate(groupGoalProgressProvider);
                      if (context.mounted) Navigator.pop(context);
                    },
                    child: Text(progress == null ? 'Set Goal' : 'Save goal'),
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

class _GroupGoalField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final TextInputType? keyboardType;

  const _GroupGoalField({
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
