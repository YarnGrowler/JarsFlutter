import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/onboarding_data.dart';
import '../../core/onboarding_redo.dart';
import '../../core/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../services/auth_service.dart';

const _kSocialProof = [
  'Rooms across 50+ cities.',
  'Rivalries settled daily.',
  'Every rank earned, never given.',
  'Join the competition.',
];

class ProcessingScreen extends ConsumerStatefulWidget {
  const ProcessingScreen({super.key});

  @override
  ConsumerState<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends ConsumerState<ProcessingScreen>
    with TickerProviderStateMixin {
  late AnimationController _barCtrl;
  late Animation<double> _barAnim;
  late AnimationController _fadeCtrl;

  int _proofIndex = 0;
  Timer? _proofTimer;
  bool _done = false;

  static const _totalMs = 6500;
  static const _proofIntervalMs = 1600;

  @override
  void initState() {
    super.initState();

    _barCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: _totalMs),
    );
    _barAnim = CurvedAnimation(
      parent: _barCtrl,
      curve: Curves.easeInOutCubic,
    );
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
      value: 1.0,
    );

    _barCtrl.forward();
    _proofTimer = Timer.periodic(
      const Duration(milliseconds: _proofIntervalMs),
      (t) {
        if (!mounted) return;
        _fadeCtrl.reverse().then((_) {
          if (!mounted) return;
          setState(
            () => _proofIndex = (_proofIndex + 1) % _kSocialProof.length,
          );
          _fadeCtrl.forward();
        });
      },
    );

    _barCtrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && !_done) {
        _done = true;
        _proofTimer?.cancel();
        Future<void>.delayed(const Duration(milliseconds: 300), () {
          if (!mounted) return;
          // Decide *before* clearing redo. A leftover Supabase session while
          // doing the normal logged-out signup funnel must NOT go('/') — that
          // can race with session=null on redirect and land on /onboarding.
          final wasReplay = OnboardingRedoSession.active;
          final session = AuthService.currentSession;
          OnboardingRedoSession.end();
          if (wasReplay && session != null) {
            context.go('/');
          } else {
            context.go('/auth/account');
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _proofTimer?.cancel();
    _barCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  String _personalizedLine(OnboardingAnswers answers) {
    final goalLine = answers.goal?.processingLine;
    final crewLine = answers.crewStatus?.processingLine;
    if (goalLine != null) return goalLine;
    if (crewLine != null) return crewLine;
    return 'Building your experience...';
  }

  @override
  Widget build(BuildContext context) {
    final answers = ref.watch(onboardingProvider);
    final reduce = MediaQuery.of(context).disableAnimations;

    return Scaffold(
      backgroundColor: JarsColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Background orbs
          Positioned(
            top: -100,
            right: -80,
            child: _orb(240, JarsColors.primary.withValues(alpha: 0.22)),
          ),
          Positioned(
            bottom: 40,
            left: -100,
            child: _orb(220, JarsColors.gold.withValues(alpha: 0.12)),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 2),

                  // Animated logo icon
                  Center(
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF9488FF),
                            JarsColors.primary,
                            Color(0xFF4A3FB8),
                          ],
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: JarsColors.primary.withValues(alpha: 0.45),
                            blurRadius: 28,
                            spreadRadius: 2,
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.12),
                          width: 1.5,
                        ),
                      ),
                      child: Icon(
                        Icons.inventory_2_rounded,
                        size: 36,
                        color: Colors.white.withValues(alpha: 0.96),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: reduce ? 1.ms : 500.ms)
                      .scale(
                        begin: const Offset(0.85, 0.85),
                        duration: reduce ? 1.ms : 600.ms,
                        curve: Curves.easeOutBack,
                      ),

                  const SizedBox(height: 40),

                  // Personalized line
                  Text(
                    _personalizedLine(answers),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: JarsColors.textPrimary,
                      height: 1.25,
                    ),
                  )
                      .animate()
                      .fadeIn(
                        delay: reduce ? 0.ms : 200.ms,
                        duration: reduce ? 1.ms : 400.ms,
                      ),

                  const SizedBox(height: 40),

                  // Progress bar
                  AnimatedBuilder(
                    animation: _barAnim,
                    builder: (_, __) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: Container(
                          height: 5,
                          color: JarsColors.border,
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: reduce ? 1.0 : _barAnim.value,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(99),
                                gradient: LinearGradient(
                                  colors: [
                                    JarsColors.primary.withValues(alpha: 0.6),
                                    JarsColors.primary,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  )
                      .animate()
                      .fadeIn(
                        delay: reduce ? 0.ms : 400.ms,
                        duration: reduce ? 1.ms : 360.ms,
                      ),

                  const SizedBox(height: 32),

                  // Social proof (fades between lines)
                  FadeTransition(
                    opacity: reduce
                        ? const AlwaysStoppedAnimation(1.0)
                        : _fadeCtrl,
                    child: Text(
                      _kSocialProof[_proofIndex],
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: JarsColors.textSecondary,
                        letterSpacing: 0.2,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(
                        delay: reduce ? 0.ms : 600.ms,
                        duration: reduce ? 1.ms : 400.ms,
                      ),

                  const Spacer(flex: 3),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _orb(double size, Color color) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 65, sigmaY: 65),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }
}
