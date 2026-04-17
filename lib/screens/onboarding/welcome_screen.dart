import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/onboarding_redo.dart';
import '../../core/theme.dart';
import '../../widgets/onboarding/onboarding_cta.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _orbCtrl;
  late Animation<double> _orbAnim;

  @override
  void initState() {
    super.initState();
    _orbCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
    _orbAnim = CurvedAnimation(parent: _orbCtrl, curve: Curves.easeInOut);

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarBrightness: Brightness.dark,
      statusBarIconBrightness: Brightness.light,
    ));
  }

  @override
  void dispose() {
    _orbCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    final size = MediaQuery.sizeOf(context);

    return Scaffold(
      backgroundColor: JarsColors.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Animated background orbs
          AnimatedBuilder(
            animation: _orbAnim,
            builder: (_, __) => Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: -80 + (reduce ? 0 : _orbAnim.value * 20),
                  right: -60 + (reduce ? 0 : _orbAnim.value * -15),
                  child: _blurOrb(220,
                      JarsColors.primary.withValues(alpha: 0.28)),
                ),
                Positioned(
                  bottom: 80 + (reduce ? 0 : _orbAnim.value * 12),
                  left: -100 + (reduce ? 0 : _orbAnim.value * 10),
                  child: _blurOrb(260,
                      JarsColors.gold.withValues(alpha: 0.14)),
                ),
                Positioned(
                  top: size.height * 0.38 + (reduce ? 0 : _orbAnim.value * 8),
                  right: 30 + (reduce ? 0 : _orbAnim.value * -5),
                  child: _blurOrb(110,
                      JarsColors.primary.withValues(alpha: 0.09)),
                ),
              ],
            ),
          ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (OnboardingRedoSession.active)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        IconButton(
                          tooltip: 'Close',
                          onPressed: () {
                            OnboardingRedoSession.end();
                            context.go('/profile');
                          },
                          icon: Icon(
                            Icons.close_rounded,
                            color: JarsColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  const Spacer(flex: 1),

                  // Editorial header (not icon-in-circle)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'JARS',
                      style: GoogleFonts.spaceMono(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 3.2,
                        color: JarsColors.gold.withValues(alpha: 0.85),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(duration: reduce ? 1.ms : 380.ms),

                  const SizedBox(height: 20),

                  Text.rich(
                    TextSpan(
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 44,
                        fontWeight: FontWeight.w800,
                        height: 1.08,
                        letterSpacing: -1.2,
                        color: JarsColors.textPrimary,
                      ),
                      children: [
                        const TextSpan(text: 'Outwork\n'),
                        TextSpan(
                          text: 'your friends.',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 44,
                            fontWeight: FontWeight.w800,
                            height: 1.08,
                            letterSpacing: -1.2,
                            color: JarsColors.gold,
                          ),
                        ),
                      ],
                    ),
                    textAlign: TextAlign.left,
                  )
                      .animate()
                      .fadeIn(
                        delay: 80.ms,
                        duration: reduce ? 1.ms : 480.ms,
                        curve: Curves.easeOut,
                      )
                      .slideX(
                        begin: reduce ? 0 : 0.04,
                        delay: 80.ms,
                        duration: 480.ms,
                        curve: Curves.easeOutCubic,
                      ),

                  const SizedBox(height: 14),

                  Text(
                    'Log workouts. Climb the board. The room keeps score - '
                    'so nobody can fake the work.',
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: JarsColors.textSecondary,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.left,
                  )
                      .animate()
                      .fadeIn(
                        delay: 200.ms,
                        duration: reduce ? 1.ms : 420.ms,
                        curve: Curves.easeOut,
                      ),

                  const SizedBox(height: 28),

                  // Product-shaped preview (mini leaderboard) — not another hero icon
                  const _WelcomeLeaderboardPreview()
                      .animate()
                      .fadeIn(
                        delay: 260.ms,
                        duration: reduce ? 1.ms : 520.ms,
                        curve: Curves.easeOut,
                      )
                      .slideY(
                        begin: reduce ? 0 : 0.05,
                        delay: 260.ms,
                        duration: 520.ms,
                        curve: Curves.easeOutCubic,
                      ),

                  const Spacer(flex: 2),

                  // CTA
                  OnboardingCta(
                    label: 'Get Started',
                    onTap: () => context.go('/onboarding/value'),
                  )
                      .animate()
                      .fadeIn(
                        delay: 700.ms,
                        duration: reduce ? 1.ms : 420.ms,
                        curve: Curves.easeOut,
                      )
                      .slideY(
                        begin: reduce ? 0 : 0.12,
                        delay: 700.ms,
                        duration: 420.ms,
                        curve: Curves.easeOutCubic,
                      ),

                  const SizedBox(height: 18),

                  // Sign in link
                  Center(
                    child: TextButton(
                      onPressed: () => context.go('/auth/login'),
                      child: Text(
                        'Already have an account? Sign in',
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: JarsColors.textSecondary,
                        ),
                      ),
                    ),
                  )
                      .animate()
                      .fadeIn(
                        delay: 850.ms,
                        duration: reduce ? 1.ms : 380.ms,
                      ),

                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Widget _blurOrb(double size, Color color) {
    return ImageFiltered(
      imageFilter: _blurFilter,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      ),
    );
  }

  static final _blurFilter =
      ImageFilter.blur(sigmaX: 65, sigmaY: 65);
}

/// Fake leaderboard strip — reads like the product, not a generic icon tile.
class _WelcomeLeaderboardPreview extends StatelessWidget {
  const _WelcomeLeaderboardPreview();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: JarsColors.surface,
        border: Border.all(color: JarsColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.leaderboard_rounded,
                size: 16,
                color: JarsColors.primary.withValues(alpha: 0.9),
              ),
              const SizedBox(width: 8),
              Text(
                'ROOM LEADERBOARD',
                style: GoogleFonts.spaceMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.3,
                  color: JarsColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _previewRow('1', 'You (next log)', '0', true),
          _previewDivider(),
          _previewRow('2', 'Alex', '1.1k', false),
          _previewDivider(),
          _previewRow('3', 'Sam', '980', false),
        ],
      ),
    );
  }

  static Widget _previewDivider() => Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Divider(
          height: 1,
          thickness: 1,
          color: JarsColors.border.withValues(alpha: 0.85),
        ),
      );

  static Widget _previewRow(String rank, String name, String pts, bool you) {
    return Row(
      children: [
        SizedBox(
          width: 28,
          child: Text(
            rank,
            style: GoogleFonts.spaceMono(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: you ? JarsColors.primary : JarsColors.textTertiary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            name,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: you ? JarsColors.textPrimary : JarsColors.textSecondary,
            ),
          ),
        ),
        Text(
          pts,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: you ? JarsColors.gold : JarsColors.primary,
          ),
        ),
      ],
    );
  }
}
