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
import 'goal_question_screen.dart' show OnboardingTopBar;

class FrequencyQuestionScreen extends ConsumerStatefulWidget {
  const FrequencyQuestionScreen({super.key});

  @override
  ConsumerState<FrequencyQuestionScreen> createState() =>
      _FrequencyQuestionScreenState();
}

class _FrequencyQuestionScreenState
    extends ConsumerState<FrequencyQuestionScreen> {
  TrainingFrequency? _selected;
  bool _advancing = false;

  Future<void> _pick(TrainingFrequency f) async {
    if (_advancing) return;
    setState(() {
      _selected = f;
      _advancing = true;
    });
    ref.read(onboardingProvider.notifier).setFrequency(f);
    await Future<void>.delayed(const Duration(milliseconds: 240));
    if (mounted) context.go('/onboarding/q3');
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
              step: 1,
              total: 4,
              onBack: () => context.go('/onboarding/q1'),
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
                      'How often do you train?',
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
                      'Helps us calibrate streak targets and room pacing.',
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
                        TrainingFrequency.low,
                        '1–2× / week',
                        Icons.hotel_class_outlined,
                        'Casual but consistent',
                      ),
                      (
                        TrainingFrequency.moderate,
                        '3–4× / week',
                        Icons.local_fire_department_outlined,
                        'Solid routine',
                      ),
                      (
                        TrainingFrequency.high,
                        '5+ / week',
                        Icons.bolt_rounded,
                        'You don\'t skip',
                      ),
                      (
                        TrainingFrequency.varies,
                        'It depends',
                        Icons.shuffle_rounded,
                        'Life happens',
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
