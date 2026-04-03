import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';
import '../../widgets/ui/auth_shell.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _lineController;
  late Animation<double> _strikeAnim;

  @override
  void initState() {
    super.initState();
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _strikeAnim = CurvedAnimation(
      parent: _lineController,
      curve: Curves.easeOutCubic,
    );
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _lineController.forward();
    });
  }

  @override
  void dispose() {
    _lineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthShell(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'JARS',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                      color: JarsColors.primary.withValues(alpha: 0.9),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: 400.ms, curve: Curves.easeOut)
                      .scale(
                        begin: const Offset(0.92, 0.92),
                        end: const Offset(1, 1),
                        curve: Curves.easeOutBack,
                      ),
                  const SizedBox(height: 40),
                  AnimatedBuilder(
                    animation: _strikeAnim,
                    builder: (context, _) {
                      return Stack(
                        alignment: Alignment.center,
                        clipBehavior: Clip.none,
                        children: [
                          Text(
                            '"Another fitness app"',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 22,
                              fontWeight: FontWeight.w400,
                              color: JarsColors.textSecondary,
                              fontStyle: FontStyle.italic,
                              height: 1.35,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          Positioned.fill(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: FractionallySizedBox(
                                widthFactor: _strikeAnim.value,
                                child: Container(
                                  height: 2.5,
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(2),
                                    gradient: LinearGradient(
                                      colors: [
                                        JarsColors.red.withValues(alpha: 0.3),
                                        JarsColors.red,
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  )
                      .animate()
                      .fadeIn(delay: 200.ms, duration: 500.ms)
                      .slideY(begin: 0.08, curve: Curves.easeOutCubic),
                  const SizedBox(height: 28),
                  Text(
                    '"A war for who works harder."',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: JarsColors.textPrimary,
                      height: 1.25,
                    ),
                    textAlign: TextAlign.center,
                  )
                      .animate()
                      .fadeIn(delay: 700.ms, duration: 600.ms)
                      .slideY(begin: 0.12, curve: Curves.easeOutCubic)
                      .shimmer(
                        delay: 1200.ms,
                        duration: 1800.ms,
                        color: JarsColors.primary.withValues(alpha: 0.25),
                      ),
                  const SizedBox(height: 36),
                  Text(
                    'Earn your rank',
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      color: JarsColors.textSecondary,
                      letterSpacing: 2,
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 1100.ms, duration: 500.ms),
                  const SizedBox(height: 52),
                  SizedBox(
                    width: double.infinity,
                    height: 58,
                    child: ElevatedButton(
                      onPressed: () => context.go('/auth/account'),
                      style: ElevatedButton.styleFrom(
                        elevation: 8,
                        shadowColor:
                            JarsColors.primary.withValues(alpha: 0.55),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'Create account',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            Icons.arrow_forward_rounded,
                            size: 22,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 1300.ms, duration: 500.ms)
                      .slideY(begin: 0.2, curve: Curves.easeOutCubic)
                      .then()
                      .shimmer(
                        delay: 400.ms,
                        duration: 2200.ms,
                        color: Colors.white.withValues(alpha: 0.12),
                      ),
                  const SizedBox(height: 14),
                  TextButton(
                    onPressed: () => context.go('/auth/login'),
                    child: Text(
                      'Already have an account? Log in',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: JarsColors.textSecondary,
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 1400.ms, duration: 450.ms),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
