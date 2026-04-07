import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/super_reaction_meta.dart';
import '../../core/theme.dart';

/// Looping mini-preview for picker & reaction chips.
class SuperReactionPreview extends StatelessWidget {
  final String id;
  final double size;

  const SuperReactionPreview({
    super.key,
    required this.id,
    this.size = 56,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: _buildInner(),
    );
  }

  Widget _buildInner() {
    switch (id) {
      case 'nova':
        return _nova();
      case 'galaxy':
        return _galaxy();
      case 'thunder':
        return _thunder();
      case 'heartbeat':
        return _heartbeat();
      case 'rainbow':
        return _rainbow();
      case 'confetti':
        return _confetti();
      case 'laser':
        return _laser();
      case 'orbit':
        return _orbit();
      case 'bloom':
        return _bloom();
      case 'meteor':
        return _meteor();
      case 'bubble':
        return _bubble();
      case 'crown':
        return _crown();
      default:
        return Center(
          child: Text(
            tryParseSuperReaction('$kSuperReactionPrefix$id')
                    ?.displayEmoji ??
                '✨',
            style: TextStyle(fontSize: size * 0.45),
          ),
        );
    }
  }

  Widget _nova() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size * 0.85,
          height: size * 0.85,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: JarsColors.primary.withValues(alpha: 0.45),
                blurRadius: size * 0.2,
                spreadRadius: size * 0.02,
              ),
            ],
          ),
        ),
        Text('🔥', style: TextStyle(fontSize: size * 0.48))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              duration: 700.ms,
              begin: const Offset(0.82, 0.82),
              end: const Offset(1.12, 1.12),
              curve: Curves.easeInOut,
            )
            .shimmer(
              duration: 1400.ms,
              color: Colors.orangeAccent.withValues(alpha: 0.35),
            ),
      ],
    );
  }

  Widget _galaxy() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text('🌌', style: TextStyle(fontSize: size * 0.42))
            .animate(onPlay: (c) => c.repeat())
            .rotate(duration: 8.seconds, begin: 0, end: 1),
        ...List.generate(4, (i) {
          final o = (i / 4) * math.pi * 2;
          return Positioned(
            left: size * 0.5 + math.cos(o) * size * 0.28 - 6,
            top: size * 0.5 + math.sin(o) * size * 0.28 - 6,
            child: Text('✨', style: TextStyle(fontSize: size * 0.16))
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 400.ms)
                .then()
                .fadeOut(duration: 400.ms),
          );
        }),
      ],
    );
  }

  Widget _thunder() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text('⚡', style: TextStyle(fontSize: size * 0.5))
            .animate(onPlay: (c) => c.repeat())
            .shake(hz: 4, rotation: 0.02, duration: 400.ms)
            .then()
            .fade(duration: 80.ms, begin: 1, end: 0.4)
            .then()
            .fade(duration: 80.ms, begin: 0.4, end: 1),
        Positioned.fill(
          child: SizedBox.expand(
            child: Container()
                .animate(onPlay: (c) => c.repeat())
                .custom(
                  duration: 600.ms,
                  builder: (_, v, __) => DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(
                        alpha: 0.12 * (1 - (v * 2 - 1).abs()),
                      ),
                    ),
                  ),
                ),
          ),
        ),
      ],
    );
  }

  Widget _heartbeat() {
    return Center(
      child: Text('💗', style: TextStyle(fontSize: size * 0.5))
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(
            duration: 500.ms,
            begin: const Offset(0.88, 0.88),
            end: const Offset(1.18, 1.18),
            curve: Curves.easeInOut,
          ),
    );
  }

  Widget _rainbow() {
    return Center(
      child: Text('🌈', style: TextStyle(fontSize: size * 0.48))
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .moveY(
            begin: -3,
            end: 3,
            duration: 900.ms,
            curve: Curves.easeInOut,
          )
          .shimmer(
            duration: 1600.ms,
            color: JarsColors.primary.withValues(alpha: 0.4),
          ),
    );
  }

  Widget _confetti() {
    const emojis = ['🎊', '✨', '🎉', '⭐'];
    return Stack(
      children: [
        Center(
          child: Text('🎊', style: TextStyle(fontSize: size * 0.4)),
        ),
        ...List.generate(4, (i) {
          final dx = (i % 2 == 0 ? -1 : 1) * size * 0.22;
          return Positioned(
            left: size * 0.5 + dx - 8,
            top: size * 0.15 + i * 6.0,
            child: Text(emojis[i], style: TextStyle(fontSize: size * 0.14))
                .animate(onPlay: (c) => c.repeat())
                .moveY(
                  begin: 0,
                  end: size * 0.38,
                  duration: (1200 + i * 150).ms,
                  curve: Curves.easeIn,
                )
                .rotate(begin: 0, end: 0.8, duration: (1200 + i * 150).ms)
                .then()
                .fadeOut(duration: 1.ms),
          );
        }),
      ],
    );
  }

  Widget _laser() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text('✴️', style: TextStyle(fontSize: size * 0.38)),
          Positioned(
            left: 0,
            right: 0,
            top: size * 0.42,
            height: 3,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.transparent,
                    JarsColors.primary.withValues(alpha: 0.95),
                    Colors.transparent,
                  ],
                ),
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .moveX(
                  begin: -size,
                  end: size,
                  duration: 1100.ms,
                  curve: Curves.easeInOut,
                ),
          ),
        ],
      ),
    );
  }

  Widget _orbit() {
    return Center(
      child: SizedBox(
        width: size * 0.92,
        height: size * 0.92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text('🛸', style: TextStyle(fontSize: size * 0.34)),
            Text(
              '● ● ●',
              style: TextStyle(
                fontSize: size * 0.12,
                letterSpacing: 2,
                color: JarsColors.primary.withValues(alpha: 0.85),
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .rotate(
                  duration: 2.4.seconds,
                  begin: 0,
                  end: 1,
                ),
          ],
        ),
      ),
    );
  }

  Widget _bloom() {
    return Center(
      child: Text('🌸', style: TextStyle(fontSize: size * 0.48))
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .scale(
            duration: 900.ms,
            begin: const Offset(0.4, 0.4),
            end: const Offset(1, 1),
            curve: Curves.elasticOut,
          )
          .fadeIn(duration: 400.ms),
    );
  }

  Widget _meteor() {
    return Stack(
      children: [
        Positioned(
          left: size * 0.08,
          top: size * 0.1,
          child: Text('☄️', style: TextStyle(fontSize: size * 0.42))
              .animate(onPlay: (c) => c.repeat())
              .moveX(begin: 0, end: size * 0.55, duration: 700.ms)
              .moveY(begin: 0, end: size * 0.5, duration: 700.ms)
              .rotate(begin: 0, end: 0.35, duration: 700.ms)
              .then()
              .fadeOut(duration: 1.ms),
        ),
        Positioned(
          left: size * 0.35,
          top: size * 0.42,
          child: Container(
            width: size * 0.45,
            height: 2,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              gradient: LinearGradient(
                colors: [
                  Colors.orangeAccent.withValues(alpha: 0),
                  Colors.orangeAccent.withValues(alpha: 0.7),
                ],
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .fade(duration: 500.ms, begin: 0, end: 1)
              .then()
              .fade(duration: 200.ms, begin: 1, end: 0),
        ),
      ],
    );
  }

  Widget _bubble() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text('🫧', style: TextStyle(fontSize: size * 0.44))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 8, end: -8, duration: 1.4.seconds)
            .scale(
              duration: 1.4.seconds,
              begin: const Offset(0.92, 0.92),
              end: const Offset(1.05, 1.05),
            ),
        Positioned(
          top: size * 0.2,
          child: Text('🫧', style: TextStyle(fontSize: size * 0.2))
              .animate(onPlay: (c) => c.repeat())
              .moveY(begin: 0, end: -size * 0.35, duration: 1.8.seconds)
              .fadeOut(duration: 400.ms, delay: 1400.ms),
        ),
      ],
    );
  }

  Widget _crown() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text('👑', style: TextStyle(fontSize: size * 0.46)),
        Positioned(
          left: size * 0.1,
          right: size * 0.1,
          top: size * 0.22,
          height: size * 0.55,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  Colors.amber.withValues(alpha: 0.55),
                  Colors.transparent,
                ],
                stops: const [0.35, 0.5, 0.65],
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat())
              .moveX(
                begin: -size,
                end: size,
                duration: 1.8.seconds,
                curve: Curves.easeInOut,
              ),
        ),
      ],
    );
  }
}
