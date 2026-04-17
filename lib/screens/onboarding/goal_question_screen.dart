import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/onboarding_data.dart';
import '../../core/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/onboarding/onboarding_progress.dart';
import '../../widgets/onboarding/onboarding_tile.dart';

class GoalQuestionScreen extends ConsumerStatefulWidget {
  const GoalQuestionScreen({super.key});

  @override
  ConsumerState<GoalQuestionScreen> createState() => _GoalQuestionScreenState();
}

class _GoalQuestionScreenState extends ConsumerState<GoalQuestionScreen> {
  OnboardingGoal? _selected;
  bool _advancing = false;

  Future<void> _pick(OnboardingGoal goal) async {
    if (_advancing) return;
    setState(() {
      _selected = goal;
      _advancing = true;
    });
    ref.read(onboardingProvider.notifier).setGoal(goal);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (mounted) context.go('/onboarding/q2');
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            OnboardingTopBar(
              step: 0,
              total: 4,
              onBack: () => context.go('/onboarding/value'),
            ),
            Expanded(
              child: IgnorePointer(
                ignoring: _advancing,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 32),
                    Text(
                      'What brings you here?',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                        height: 1.15,
                        letterSpacing: -0.5,
                        color: JarsColors.textPrimary,
                      ),
                    )
                        .animate()
                        .fadeIn(duration: reduce ? 1.ms : 340.ms)
                        .slideY(
                          begin: reduce ? 0 : 0.06,
                          duration: 340.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    const SizedBox(height: 8),
                    Text(
                      'This shapes how your room experience feels.',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: JarsColors.textSecondary,
                        height: 1.4,
                      ),
                    )
                        .animate()
                        .fadeIn(
                          delay: reduce ? 0.ms : 60.ms,
                          duration: reduce ? 1.ms : 300.ms,
                        ),
                    const SizedBox(height: 32),
                    for (final entry in [
                      (
                        OnboardingGoal.competition,
                        'Competition',
                        Icons.emoji_events_rounded,
                        'I want to beat my crew',
                      ),
                      (
                        OnboardingGoal.accountability,
                        'Accountability',
                        Icons.people_alt_rounded,
                        'I want us all to stay consistent',
                      ),
                      (
                        OnboardingGoal.tracking,
                        'Just tracking',
                        Icons.bar_chart_rounded,
                        'I want to see my own progress',
                      ),
                    ].indexed)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: OnboardingTile(
                          label: entry.$2.$2,
                          icon: entry.$2.$3,
                          subtitle: entry.$2.$4,
                          selected: _selected == entry.$2.$1,
                          onTap: () => _pick(entry.$2.$1),
                          staggerIndex: entry.$1,
                        ),
                      ),
                    const Spacer(),
                  ],
                ),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class OnboardingTopBar extends StatelessWidget {
  const OnboardingTopBar({
    super.key,
    required this.step,
    required this.total,
    required this.onBack,
  });

  final int step;
  final int total;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
            color: JarsColors.textSecondary,
            onPressed: onBack,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: OnboardingProgress(total: total, current: step),
            ),
          ),
          Text(
            '${step + 1} of $total',
            style: GoogleFonts.spaceMono(
              fontSize: 11,
              color: JarsColors.textTertiary,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}
