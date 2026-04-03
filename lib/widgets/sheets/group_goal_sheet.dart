import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/goal_provider.dart';
import '../../services/goal_service.dart';

/// Admin: set / replace room group goal (same flow as Profile → room settings).
void showGroupGoalSheet(
  BuildContext context,
  WidgetRef ref,
  String roomId,
) {
  final targetController = TextEditingController();
  final daysController = TextEditingController(text: '7');
  final descController = TextEditingController();

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: JarsColors.surfaceRaised,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      return SafeArea(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            24,
            24,
            MediaQuery.of(ctx).viewInsets.bottom + 24,
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
              _GroupGoalField(
                label: 'Target Points (total)',
                controller: targetController,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _GroupGoalField(
                label: 'Duration (days)',
                controller: daysController,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              _GroupGoalField(
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
                    final target = int.tryParse(targetController.text);
                    final days = int.tryParse(daysController.text);
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
                    ref.invalidate(groupGoalProgressProvider);
                    if (ctx.mounted) Navigator.pop(ctx);
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
