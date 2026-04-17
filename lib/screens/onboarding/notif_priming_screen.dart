import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';
import '../../providers/onboarding_provider.dart';
import '../../services/notification_service.dart';
import '../../widgets/onboarding/onboarding_cta.dart';

class NotifPrimingScreen extends ConsumerStatefulWidget {
  const NotifPrimingScreen({super.key});

  @override
  ConsumerState<NotifPrimingScreen> createState() => _NotifPrimingScreenState();
}

class _NotifPrimingScreenState extends ConsumerState<NotifPrimingScreen>
    with SingleTickerProviderStateMixin {
  bool _loading = false;

  late AnimationController _bellCtrl;

  @override
  void initState() {
    super.initState();
    _bellCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) _bellCtrl.forward().then((_) {
        Future.delayed(const Duration(milliseconds: 1200), () {
          if (mounted) {
            _bellCtrl.reset();
            _bellCtrl.forward();
          }
        });
      });
    });
  }

  @override
  void dispose() {
    _bellCtrl.dispose();
    super.dispose();
  }

  void _skip() {
    ref.read(onboardingProvider.notifier).markNotifPrimingSeen();
    context.go('/auth/room-entry');
  }

  Future<void> _enable() async {
    if (_loading) return;
    setState(() => _loading = true);
    ref.read(onboardingProvider.notifier).markNotifPrimingSeen();
    try {
      await NotificationService.registerToken();
    } catch (_) {
      // Permission denied or device doesn't support — proceed silently.
    }
    if (mounted) context.go('/auth/room-entry');
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(flex: 2),

              // Bell icon with wiggle
              Center(
                child: AnimatedBuilder(
                  animation: _bellCtrl,
                  builder: (_, child) {
                    final angle = reduce
                        ? 0.0
                        : 0.18 *
                            (1 - _bellCtrl.value) *
                            ((_bellCtrl.value * 8).floor() % 2 == 0 ? 1 : -1);
                    return Transform.rotate(
                      angle: angle,
                      child: child,
                    );
                  },
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      color: JarsColors.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: JarsColors.primary.withValues(alpha: 0.28),
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      Icons.notifications_active_rounded,
                      size: 48,
                      color: JarsColors.primary,
                    ),
                  ),
                ),
              )
                  .animate()
                  .fadeIn(duration: reduce ? 1.ms : 480.ms)
                  .scale(
                    begin: const Offset(0.78, 0.78),
                    duration: reduce ? 1.ms : 560.ms,
                    curve: Curves.easeOutBack,
                  ),

              const SizedBox(height: 44),

              // Headline
              Text(
                'Know when your crew logs.',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                  letterSpacing: -0.4,
                  color: JarsColors.textPrimary,
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduce ? 0.ms : 200.ms,
                    duration: reduce ? 1.ms : 400.ms,
                  )
                  .slideY(
                    begin: reduce ? 0 : 0.06,
                    delay: 200.ms,
                    duration: 400.ms,
                    curve: Curves.easeOutCubic,
                  ),

              const SizedBox(height: 16),

              // Body
              Text(
                'Get a heads up when someone posts a workout — so you can react, or one-up them. We send one alert per session max.',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  color: JarsColors.textSecondary,
                  height: 1.55,
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduce ? 0.ms : 340.ms,
                    duration: reduce ? 1.ms : 380.ms,
                  ),

              const Spacer(flex: 3),

              OnboardingCta(
                label: 'Turn on alerts',
                onTap: _enable,
                loading: _loading,
                hapticStyle: HapticStyle.medium,
              )
                  .animate()
                  .fadeIn(
                    delay: reduce ? 0.ms : 500.ms,
                    duration: reduce ? 1.ms : 380.ms,
                  )
                  .slideY(
                    begin: reduce ? 0 : 0.1,
                    delay: 500.ms,
                    duration: 380.ms,
                    curve: Curves.easeOutCubic,
                  ),

              const SizedBox(height: 16),

              Center(
                child: TextButton(
                  onPressed: _skip,
                  child: Text(
                    'Not now',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: JarsColors.textSecondary,
                    ),
                  ),
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduce ? 0.ms : 640.ms,
                    duration: reduce ? 1.ms : 340.ms,
                  ),

              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }
}
