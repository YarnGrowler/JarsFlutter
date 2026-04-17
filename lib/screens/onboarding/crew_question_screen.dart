import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/onboarding_data.dart';
import '../../core/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/onboarding/onboarding_progress.dart';
import 'goal_question_screen.dart' show OnboardingTopBar;

class CrewQuestionScreen extends ConsumerStatefulWidget {
  const CrewQuestionScreen({super.key});

  @override
  ConsumerState<CrewQuestionScreen> createState() => _CrewQuestionScreenState();
}

class _CrewQuestionScreenState extends ConsumerState<CrewQuestionScreen> {
  CrewStatus? _selected;
  bool _advancing = false;

  Future<void> _pick(CrewStatus s) async {
    if (_advancing) return;
    HapticFeedback.lightImpact();
    setState(() {
      _selected = s;
      _advancing = true;
    });
    ref.read(onboardingProvider.notifier).setCrewStatus(s);
    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (mounted) context.go('/onboarding/processing');
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
              step: 3,
              total: 4,
              onBack: () => context.go('/onboarding/q3'),
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
                      'Got a crew already?',
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
                      'We\'ll drop you straight into the right setup.',
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
                    const SizedBox(height: 48),

                    // Big binary choice cards
                    _BigChoiceCard(
                      emoji: '🔑',
                      title: 'Yes, I have a code',
                      subtitle: 'Someone sent me an invite — join their room',
                      selected: _selected == CrewStatus.hasCode,
                      onTap: () => _pick(CrewStatus.hasCode),
                      staggerIndex: 0,
                    ),
                    const SizedBox(height: 16),
                    _BigChoiceCard(
                      emoji: '🏗️',
                      title: "Nah, I'm starting fresh",
                      subtitle: 'Create a room and pull in the crew',
                      selected: _selected == CrewStatus.startingFresh,
                      onTap: () => _pick(CrewStatus.startingFresh),
                      staggerIndex: 1,
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

class _BigChoiceCard extends StatefulWidget {
  const _BigChoiceCard({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
    required this.staggerIndex,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;
  final int staggerIndex;

  @override
  State<_BigChoiceCard> createState() => _BigChoiceCardState();
}

class _BigChoiceCardState extends State<_BigChoiceCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
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
          scale: 1.0 - _ctrl.value * 0.015,
          child: child,
        ),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: widget.selected
                ? JarsColors.primary.withValues(alpha: 0.13)
                : JarsColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: widget.selected
                  ? JarsColors.primary.withValues(alpha: 0.65)
                  : JarsColors.border,
              width: widget.selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              Text(widget.emoji, style: const TextStyle(fontSize: 32)),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: JarsColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: JarsColors.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.selected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: const BoxDecoration(
                    color: JarsColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded,
                      size: 15, color: Colors.white),
                ),
            ],
          ),
        ),
      ),
    )
        .animate(
          delay: reduce
              ? Duration.zero
              : Duration(milliseconds: widget.staggerIndex * 65),
        )
        .fadeIn(duration: reduce ? 1.ms : 300.ms)
        .slideY(
          begin: reduce ? 0 : 0.06,
          duration: 300.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
