import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/onboarding/onboarding_cta.dart';
import '../../widgets/onboarding/onboarding_progress.dart';
import 'goal_question_screen.dart' show OnboardingTopBar;

const _kExerciseOptions = [
  ('Pull-ups', Icons.fitness_center_rounded),
  ('Push-ups', Icons.sports_martial_arts_rounded),
  ('Squats', Icons.directions_run_rounded),
  ('Planks', Icons.timer_outlined),
  ('Running', Icons.directions_run_rounded),
  ('Weights', Icons.fitness_center_rounded),
  ('Cycling', Icons.pedal_bike_rounded),
  ('Swimming', Icons.pool_rounded),
  ('Yoga', Icons.self_improvement_rounded),
  ('Rowing', Icons.rowing_rounded),
];

class ExercisesQuestionScreen extends ConsumerStatefulWidget {
  const ExercisesQuestionScreen({super.key});

  @override
  ConsumerState<ExercisesQuestionScreen> createState() =>
      _ExercisesQuestionScreenState();
}

class _ExercisesQuestionScreenState
    extends ConsumerState<ExercisesQuestionScreen> {
  final Set<String> _selected = {};
  bool _advancing = false;

  void _toggle(String name) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selected.contains(name)) {
        _selected.remove(name);
      } else {
        _selected.add(name);
      }
    });
  }

  Future<void> _advance() async {
    if (_advancing) return;
    setState(() => _advancing = true);
    ref.read(onboardingProvider.notifier).setExercises(_selected.toList());
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (mounted) context.go('/onboarding/q4');
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
              step: 2,
              total: 4,
              onBack: () => context.go('/onboarding/q2'),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 32, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'What do you train?',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                      letterSpacing: -0.5,
                      color: JarsColors.textPrimary,
                    ),
                  )
                      .animate()
                      .fadeIn(duration: reduce ? 1.ms : 320.ms)
                      .slideY(
                        begin: reduce ? 0 : 0.06,
                        duration: 320.ms,
                        curve: Curves.easeOutCubic,
                      ),
                  const SizedBox(height: 8),
                  Text(
                    'We\'ll pin your favourites in the log screen. Pick any.',
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
                ],
              ),
            ),
            const SizedBox(height: 24),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: GridView.builder(
                  itemCount: _kExerciseOptions.length,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: 12,
                    crossAxisSpacing: 12,
                    childAspectRatio: 2.4,
                  ),
                  itemBuilder: (context, i) {
                    final opt = _kExerciseOptions[i];
                    final name = opt.$1;
                    final icon = opt.$2;
                    final isSelected = _selected.contains(name);
                    return _ExerciseChip(
                      label: name,
                      icon: icon,
                      selected: isSelected,
                      onTap: () => _toggle(name),
                      staggerIndex: i,
                    );
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 28),
              child: Column(
                children: [
                  if (_selected.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        'Tap any to select — or skip if you\'ll log custom.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: JarsColors.textTertiary,
                        ),
                      ),
                    ),
                  OnboardingCta(
                    label: _selected.isEmpty ? 'Skip for now' : 'Done',
                    onTap: _advance,
                    loading: _advancing,
                    hapticStyle: HapticStyle.medium,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseChip extends StatefulWidget {
  const _ExerciseChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    required this.staggerIndex,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  final int staggerIndex;

  @override
  State<_ExerciseChip> createState() => _ExerciseChipState();
}

class _ExerciseChipState extends State<_ExerciseChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 130),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.scale(
          scale: 1.0 - _ctrl.value * 0.025,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: widget.selected
                ? JarsColors.primary.withValues(alpha: 0.16)
                : JarsColors.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: widget.selected
                  ? JarsColors.primary.withValues(alpha: 0.6)
                  : JarsColors.border,
              width: widget.selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Icon(
                widget.icon,
                size: 18,
                color: widget.selected
                    ? JarsColors.primary
                    : JarsColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.label,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: widget.selected
                        ? JarsColors.textPrimary
                        : JarsColors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    )
        .animate(
          delay: reduce
              ? Duration.zero
              : Duration(milliseconds: widget.staggerIndex * 30),
        )
        .fadeIn(duration: reduce ? 1.ms : 260.ms)
        .slideY(
          begin: reduce ? 0 : 0.06,
          duration: 260.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
