import 'dart:ui';
import 'package:flutter/material.dart';
import '../../bootstrap/deploy_label.dart';
import '../../core/theme.dart';

/// Dark gradient backdrop + soft glow orbs for auth / onboarding flows.
class AuthShell extends StatelessWidget {
  final Widget child;
  final bool showOrbs;

  const AuthShell({
    super.key,
    required this.child,
    this.showOrbs = true,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF06060C),
                JarsColors.background,
                Color(0xFF0E0E18),
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
        ),
        if (showOrbs) ...[
          Positioned(
            top: -80,
            right: -60,
            child: _blurOrb(180, JarsColors.primary.withValues(alpha: 0.22)),
          ),
          Positioned(
            bottom: 120,
            left: -100,
            child: _blurOrb(200, JarsColors.gold.withValues(alpha: 0.12)),
          ),
          Positioned(
            top: 200,
            left: 40,
            child: _blurOrb(100, JarsColors.primary.withValues(alpha: 0.08)),
          ),
        ],
        Stack(
          fit: StackFit.expand,
          children: [
            child,
            Positioned(
              left: 12,
              right: 12,
              bottom: 0,
              child: SafeArea(
                top: false,
                minimum: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'Jars $kJarsDeployLabel',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    letterSpacing: 0.3,
                    color: JarsColors.textTertiary.withValues(alpha: 0.9),
                  ),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  static Widget _blurOrb(double size, Color color) {
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
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
}
