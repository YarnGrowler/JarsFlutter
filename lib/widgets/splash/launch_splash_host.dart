import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';

/// Wraps the app and shows a branded splash on every process start: logo, then slides left to reveal the app.
class LaunchSplashHost extends StatefulWidget {
  final Widget child;

  const LaunchSplashHost({super.key, required this.child});

  @override
  State<LaunchSplashHost> createState() => _LaunchSplashHostState();
}

class _LaunchSplashHostState extends State<LaunchSplashHost>
    with SingleTickerProviderStateMixin {
  bool _showSplash = true;
  late final AnimationController _slideController;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1, 0),
    ).animate(
      CurvedAnimation(
        parent: _slideController,
        curve: Curves.easeInOutCubicEmphasized,
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleExit());
  }

  Future<void> _scheduleExit() async {
    await Future.delayed(const Duration(milliseconds: 1550));
    if (!mounted) return;
    await _slideController.forward();
    if (!mounted) return;
    setState(() => _showSplash = false);
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_showSplash)
          Positioned.fill(
            child: SlideTransition(
              position: _slideAnimation,
              child: const SizedBox.expand(child: _JarsSplashPanel()),
            ),
          ),
      ],
    );
  }
}

class _JarsSplashPanel extends StatelessWidget {
  const _JarsSplashPanel();

  static Widget _orb(double size, Color color, double blur) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF05050A),
                  JarsColors.background,
                  Color(0xFF0C0C16),
                ],
                stops: [0.0, 0.42, 1.0],
              ),
            ),
          ),
          Positioned(
            top: -100,
            right: -80,
            child: _orb(220, JarsColors.primary.withValues(alpha: 0.2), 70),
          ),
          Positioned(
            bottom: 80,
            left: -120,
            child: _orb(260, JarsColors.gold.withValues(alpha: 0.14), 75),
          ),
          Positioned(
            top: 180,
            left: 20,
            child: _orb(120, JarsColors.primary.withValues(alpha: 0.1), 55),
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 108,
                    height: 108,
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
                          blurRadius: 36,
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
                      size: 54,
                      color: Colors.white.withValues(alpha: 0.96),
                    ),
                  ),
                  const SizedBox(height: 28),
                  Text(
                    'JARS',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 46,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 10,
                      height: 1.0,
                      color: JarsColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Earn Your Rank',
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.6,
                      color: JarsColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    height: 2,
                    width: 56,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(2),
                      gradient: LinearGradient(
                        colors: [
                          JarsColors.gold.withValues(alpha: 0.2),
                          JarsColors.gold,
                          JarsColors.gold.withValues(alpha: 0.2),
                        ],
                      ),
                    ),
                  ),
                ],
              )
                  .animate()
                  .fadeIn(duration: 520.ms, curve: Curves.easeOutCubic)
                  .scale(
                    begin: const Offset(0.9, 0.9),
                    end: const Offset(1, 1),
                    duration: 640.ms,
                    curve: Curves.easeOutCubic,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
