import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../core/super_reaction_meta.dart';
import '../../services/auth_service.dart';
import '../../services/reaction_service.dart';

/// On app open, if others reacted to your logs since last visit, plays a
/// reverse-rain of emojis rising from the bottom.
class ReactionRainHost extends ConsumerStatefulWidget {
  final Widget child;

  const ReactionRainHost({super.key, required this.child});

  @override
  ConsumerState<ReactionRainHost> createState() => _ReactionRainHostState();
}

class _ReactionRainHostState extends ConsumerState<ReactionRainHost>
    with SingleTickerProviderStateMixin {
  static const _prefsKey = 'jars_last_reaction_poll_utc';

  List<_RainParticle>? _particles;
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..addListener(() {
        if (mounted) setState(() {});
      });
    WidgetsBinding.instance.addPostFrameCallback((_) => _poll());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _poll() async {
    if (!mounted) return;
    if (AuthService.currentSession == null) return;

    final prefs = await SharedPreferences.getInstance();
    final lastStr = prefs.getString(_prefsKey);
    final since = lastStr != null
        ? DateTime.tryParse(lastStr) ??
            DateTime.now().toUtc().subtract(const Duration(days: 3))
        : DateTime.now().toUtc().subtract(const Duration(days: 14));

    List<String> emojis;
    try {
      emojis = await ReactionService.getNewReactionEmojisOnMyLogsSince(since);
    } catch (_) {
      emojis = [];
    }

    await prefs.setString(_prefsKey, DateTime.now().toUtc().toIso8601String());

    if (!mounted || emojis.isEmpty) return;

    final rng = math.Random();
    final w = MediaQuery.sizeOf(context).width;
    _particles = emojis
        .map(
          (e) => _RainParticle(
            displayText: displayEmojiForStoredReaction(e),
            isSuper: storedReactionIsSuper(e),
            left: rng.nextDouble() * (w - 48),
            delay: rng.nextDouble() * 0.35,
            duration: 0.55 + rng.nextDouble() * 0.45,
          ),
        )
        .toList();

    setState(() {});
    _ctrl.forward(from: 0);
    await Future<void>.delayed(const Duration(milliseconds: 4500));
    if (mounted) {
      setState(() {
        _particles = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_particles != null)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _RainPainter(
                  particles: _particles!,
                  t: _ctrl.value,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _RainParticle {
  /// Single grapheme to paint (never raw `sr:*`).
  final String displayText;
  final bool isSuper;
  final double left;
  final double delay;
  final double duration;

  _RainParticle({
    required this.displayText,
    required this.isSuper,
    required this.left,
    required this.delay,
    required this.duration,
  });
}

class _RainPainter extends CustomPainter {
  final List<_RainParticle> particles;
  final double t;

  _RainPainter({required this.particles, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final localT = ((t - p.delay) / p.duration).clamp(0.0, 1.0);
      if (localT <= 0) continue;
      final y = size.height - localT * (size.height * 0.92);
      final opacity = (1 - localT) * 0.95;
      final superBoost = p.isSuper ? 1.35 : 1.0;
      final baseSize = (22 + (1 - localT) * 18) * superBoost;
      if (p.isSuper) {
        final glow = TextPainter(
          text: TextSpan(
            text: p.displayText,
            style: TextStyle(
              fontSize: baseSize + 6,
              color: const Color(0xFFB070FF).withValues(alpha: opacity * 0.35),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        glow.paint(canvas, Offset(p.left - 2, y - 1));
      }
      final tp = TextPainter(
        text: TextSpan(
          text: p.displayText,
          style: TextStyle(
            fontSize: baseSize,
            color: p.isSuper
                ? const Color(0xFFE8C8FF).withValues(alpha: opacity)
                : Colors.white.withValues(alpha: opacity),
            shadows: p.isSuper
                ? [
                    Shadow(
                      color: const Color(0xFF9D4EDD).withValues(alpha: 0.9),
                      blurRadius: 14,
                    ),
                  ]
                : null,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(p.left, y));
    }
  }

  @override
  bool shouldRepaint(covariant _RainPainter old) => old.t != t;
}
