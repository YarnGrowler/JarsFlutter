import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';

/// Primary CTA button for onboarding screens.
/// Scales down on press (spring feedback), fires haptic on tap.
class OnboardingCta extends StatefulWidget {
  const OnboardingCta({
    super.key,
    required this.label,
    required this.onTap,
    this.enabled = true,
    this.loading = false,
    this.hapticStyle = HapticStyle.medium,
  });

  final String label;
  final VoidCallback? onTap;
  final bool enabled;
  final bool loading;
  final HapticStyle hapticStyle;

  @override
  State<OnboardingCta> createState() => _OnboardingCtaState();
}

enum HapticStyle { light, medium, heavy, success }

class _OnboardingCtaState extends State<OnboardingCta>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _fireHaptic() {
    switch (widget.hapticStyle) {
      case HapticStyle.light:
        HapticFeedback.lightImpact();
        break;
      case HapticStyle.medium:
        HapticFeedback.mediumImpact();
        break;
      case HapticStyle.heavy:
        HapticFeedback.heavyImpact();
        break;
      case HapticStyle.success:
        HapticFeedback.mediumImpact();
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.enabled && !widget.loading;
    return AnimatedBuilder(
      animation: _scale,
      builder: (context, child) => Transform.scale(
        scale: _scale.value,
        child: child,
      ),
      child: GestureDetector(
        onTapDown: active ? (_) => _ctrl.forward() : null,
        onTapUp: active
            ? (_) async {
                await _ctrl.reverse();
                _fireHaptic();
                widget.onTap?.call();
              }
            : null,
        onTapCancel: () => _ctrl.reverse(),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(9999),
            color: active ? JarsColors.primary : JarsColors.surfaceRaised,
            boxShadow: active
                ? [
                    BoxShadow(
                      color: JarsColors.primary.withValues(alpha: 0.42),
                      blurRadius: 20,
                      offset: const Offset(0, 6),
                    ),
                  ]
                : [],
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : Text(
                    widget.label,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.3,
                      color: active
                          ? Colors.white
                          : JarsColors.textSecondary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
