import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/theme.dart';

const _kKey = 'first_run_log_hint_seen_v1';

/// Clears the "seen" flag so the +Log coach mark can show again (e.g. replay onboarding).
Future<void> clearFirstRunLogHintPrefs() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kKey);
}

/// Shows a single coach mark tooltip pointing up at the bottom nav Log button
/// the first time a user with a room opens RoomScreen.
class FirstRunCoachMark extends StatefulWidget {
  const FirstRunCoachMark({super.key, required this.child});

  final Widget child;

  @override
  State<FirstRunCoachMark> createState() => _FirstRunCoachMarkState();
}

class _FirstRunCoachMarkState extends State<FirstRunCoachMark> {
  bool _show = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _checkSeen();
  }

  Future<void> _checkSeen() async {
    final prefs = await SharedPreferences.getInstance();
    final seen = prefs.getBool(_kKey) ?? false;
    if (!mounted) return;
    setState(() {
      _show = !seen;
      _loaded = true;
    });
  }

  Future<void> _dismiss() async {
    HapticFeedback.lightImpact();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kKey, true);
    if (!mounted) return;
    setState(() => _show = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (_loaded && _show)
          Positioned(
            // Positioned above the bottom nav bar; the nav bar is ~80px high.
            bottom: 72,
            left: 0,
            right: 0,
            child: GestureDetector(
              onTap: _dismiss,
              child: Center(
                child: _CoachBubble(onDismiss: _dismiss),
              ),
            ),
          ),
      ],
    );
  }
}

class _CoachBubble extends StatelessWidget {
  const _CoachBubble({required this.onDismiss});
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return GestureDetector(
      onTap: onDismiss,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        decoration: BoxDecoration(
          color: JarsColors.primary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: JarsColors.primary.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.fitness_center_rounded,
                    color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    'Log your first workout to earn points.',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Caret pointing down toward the Log button
            CustomPaint(
              size: const Size(16, 8),
              painter: _CaretPainter(color: JarsColors.primary),
            ),
          ],
        ),
      )
          .animate()
          .fadeIn(duration: reduce ? 1.ms : 400.ms, curve: Curves.easeOut)
          .slideY(
            begin: reduce ? 0 : 0.1,
            duration: 400.ms,
            curve: Curves.easeOutBack,
          ),
    );
  }
}

class _CaretPainter extends CustomPainter {
  const _CaretPainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width / 2, size.height)
      ..lineTo(size.width, 0)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
