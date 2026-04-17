import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/theme.dart';

/// Selectable tile used in onboarding question screens.
/// Staggers in on mount, scales on selection, fires haptic.
class OnboardingTile extends StatefulWidget {
  const OnboardingTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
    this.subtitle,
    this.staggerIndex = 0,
  });

  final String label;
  final IconData icon;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;
  final int staggerIndex;

  @override
  State<OnboardingTile> createState() => _OnboardingTileState();
}

class _OnboardingTileState extends State<OnboardingTile>
    with SingleTickerProviderStateMixin {
  late AnimationController _scaleCtrl;
  late Animation<double> _scaleAnim;
  bool _pressing = false;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
    );
    _scaleAnim = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _scaleCtrl, curve: Curves.easeOutBack),
    );
  }

  @override
  void didUpdateWidget(covariant OnboardingTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      _scaleCtrl.forward().then((_) => _scaleCtrl.reverse());
    }
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _scaleAnim,
      builder: (context, child) {
        return Transform.scale(
          scale: widget.selected ? _scaleAnim.value : 1.0,
          child: child,
        );
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _pressing = true),
        onTapUp: (_) {
          setState(() => _pressing = false);
          _handleTap();
        },
        onTapCancel: () => setState(() => _pressing = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          decoration: BoxDecoration(
            color: widget.selected
                ? JarsColors.primary.withValues(alpha: 0.16)
                : _pressing
                    ? JarsColors.surface.withValues(alpha: 0.8)
                    : JarsColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: widget.selected
                  ? JarsColors.primary.withValues(alpha: 0.65)
                  : JarsColors.border,
              width: widget.selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: widget.selected
                      ? JarsColors.primary.withValues(alpha: 0.22)
                      : JarsColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  widget.icon,
                  size: 22,
                  color: widget.selected
                      ? JarsColors.primary
                      : JarsColors.textSecondary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.label,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: widget.selected
                            ? JarsColors.textPrimary
                            : JarsColors.textPrimary.withValues(alpha: 0.85),
                      ),
                    ),
                    if (widget.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle!,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: JarsColors.textSecondary,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: widget.selected ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 180),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: JarsColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 14,
                    color: Colors.white,
                  ),
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
              : Duration(milliseconds: widget.staggerIndex * 55),
        )
        .fadeIn(duration: reduce ? 1.ms : 280.ms)
        .slideY(
          begin: reduce ? 0 : 0.05,
          duration: 280.ms,
          curve: Curves.easeOutCubic,
        );
  }
}
