import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../core/super_reaction_meta.dart';
import '../../core/theme.dart';

/// Looping mini-preview for picker & reaction chips — each id has a distinct motion language.
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
        return _feralFire();
      case 'galaxy':
        return _voidSpiral();
      case 'thunder':
        return _mainCharacter();
      case 'heartbeat':
        return _unhinged();
      case 'rainbow':
        return _chaosRainbow();
      case 'confetti':
        return _touchGrass();
      case 'laser':
        return _doomScroll();
      case 'orbit':
        return _ufoOrbit();
      case 'bloom':
        return _delulu();
      case 'meteor':
        return _skillIssue();
      case 'bubble':
        return _gremlin();
      case 'crown':
        return _rentFree();
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

  Widget _feralFire() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size * 0.9,
          height: size * 0.9,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.deepOrange.withValues(alpha: 0.5),
                blurRadius: size * 0.25,
              ),
            ],
          ),
        ),
        Text('🔥', style: TextStyle(fontSize: size * 0.5))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .shake(
              hz: 5,
              rotation: 0.06,
              duration: 220.ms,
              curve: Curves.easeInOut,
            )
            .scale(
              duration: 220.ms,
              begin: const Offset(1, 1),
              end: const Offset(1.18, 0.92),
            ),
      ],
    );
  }

  Widget _voidSpiral() {
    return Stack(
      alignment: Alignment.center,
      children: [
        ...List.generate(6, (i) {
          final a = i / 6 * math.pi * 2;
          return Positioned(
            left: size * 0.5 + math.cos(a) * size * 0.02 - 3,
            top: size * 0.5 + math.sin(a) * size * 0.02 - 3,
            child: Text(
              '·',
              style: TextStyle(
                fontSize: size * 0.14,
                color: JarsColors.primary.withValues(alpha: 0.4 + i * 0.08),
              ),
            ),
          );
        }),
        Text('🌀', style: TextStyle(fontSize: size * 0.46))
            .animate(onPlay: (c) => c.repeat())
            .rotate(duration: 3.2.seconds, begin: 0, end: 1)
            .scale(
              duration: 3.2.seconds,
              begin: const Offset(0.85, 0.85),
              end: const Offset(1.08, 1.08),
              curve: Curves.easeInOut,
            ),
      ],
    );
  }

  Widget _mainCharacter() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Container(
          width: size * 0.88,
          height: size * 0.52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.35),
              width: 2,
            ),
          ),
        ),
        Text('🎬', style: TextStyle(fontSize: size * 0.42))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveX(begin: -2, end: 2, duration: 180.ms)
            .then()
            .shimmer(
              duration: 400.ms,
              color: Colors.amber.withValues(alpha: 0.4),
            ),
      ],
    );
  }

  Widget _unhinged() {
    return Center(
      child: Text('😵‍💫', style: TextStyle(fontSize: size * 0.48))
          .animate(onPlay: (c) => c.repeat())
          .rotate(
            duration: 280.ms,
            begin: -0.04,
            end: 0.04,
            curve: Curves.easeInOut,
          )
          .then()
          .rotate(
            duration: 280.ms,
            begin: 0.04,
            end: -0.04,
            curve: Curves.easeInOut,
          ),
    );
  }

  Widget _chaosRainbow() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ...List.generate(4, (i) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 3),
            child: Container(
              width: size * (0.42 + i * 0.06),
              height: 3,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                gradient: LinearGradient(
                  colors: [
                    Colors.red.withValues(alpha: 0.45),
                    Colors.amber.withValues(alpha: 0.45),
                    Colors.green.withValues(alpha: 0.45),
                    Colors.blue.withValues(alpha: 0.45),
                  ],
                ),
              ),
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .moveX(
                  begin: -5,
                  end: 5,
                  duration: (350 + i * 70).ms,
                ),
          );
        }),
        Text('🌈', style: TextStyle(fontSize: size * 0.36))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .rotate(begin: -0.1, end: 0.1, duration: 450.ms),
      ],
    );
  }

  Widget _touchGrass() {
    return Stack(
      alignment: Alignment.bottomCenter,
      children: [
        Text('🌿', style: TextStyle(fontSize: size * 0.5))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 2, end: -4, duration: 900.ms)
            .rotate(begin: -0.06, end: 0.06, duration: 900.ms),
        Positioned(
          bottom: 0,
          child: Container(
            width: size * 0.65,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(2),
              color: Colors.green.withValues(alpha: 0.25),
            ),
          ),
        ),
      ],
    );
  }

  Widget _doomScroll() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: size * 0.55,
            height: size * 0.72,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A24),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: JarsColors.border),
            ),
            child: Text('📱', style: TextStyle(fontSize: size * 0.38)),
          ),
          Positioned(
            left: size * 0.18,
            right: size * 0.18,
            top: size * 0.22,
            child: Column(
              children: List.generate(
                4,
                (i) => Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(1),
                      color: JarsColors.textTertiary.withValues(alpha: 0.25),
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat())
                      .moveY(
                        begin: 0,
                        end: size * 0.18,
                        duration: (1400 + i * 120).ms,
                        curve: Curves.linear,
                      ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ufoOrbit() {
    return Center(
      child: SizedBox(
        width: size * 0.92,
        height: size * 0.92,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Text('🛸', style: TextStyle(fontSize: size * 0.36)),
            Text(
              '● ● ●',
              style: TextStyle(
                fontSize: size * 0.11,
                letterSpacing: 2,
                color: JarsColors.primary.withValues(alpha: 0.9),
              ),
            )
                .animate(onPlay: (c) => c.repeat())
                .rotate(duration: 2.2.seconds, begin: 0, end: 1),
          ],
        ),
      ),
    );
  }

  Widget _delulu() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text('💭', style: TextStyle(fontSize: size * 0.28))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveX(begin: -size * 0.2, end: size * 0.2, duration: 1.2.seconds)
            .fadeOut(duration: 600.ms, delay: 600.ms),
        Text('🫧', style: TextStyle(fontSize: size * 0.46))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .scale(
              duration: 800.ms,
              begin: const Offset(0.75, 0.75),
              end: const Offset(1.1, 1.1),
              curve: Curves.elasticOut,
            ),
      ],
    );
  }

  Widget _skillIssue() {
    return Center(
      child: Text('💀', style: TextStyle(fontSize: size * 0.52))
          .animate(onPlay: (c) => c.repeat(reverse: true))
          .shake(hz: 3, rotation: 0.12, duration: 100.ms)
          .then(delay: 80.ms)
          .scale(
            duration: 120.ms,
            begin: const Offset(1, 1),
            end: const Offset(1.15, 1.15),
          )
          .then()
          .scale(
            duration: 120.ms,
            begin: const Offset(1.15, 1.15),
            end: const Offset(1, 1),
          ),
    );
  }

  Widget _gremlin() {
    return Stack(
      alignment: Alignment.center,
      children: [
        Text('🧌', style: TextStyle(fontSize: size * 0.5))
            .animate(onPlay: (c) => c.repeat(reverse: true))
            .moveY(begin: 0, end: -6, duration: 160.ms)
            .then()
            .moveY(begin: -6, end: 0, duration: 160.ms),
        Positioned(
          top: size * 0.08,
          child: Text('✨', style: TextStyle(fontSize: size * 0.16))
              .animate(onPlay: (c) => c.repeat())
              .fadeIn(duration: 100.ms)
              .then()
              .fadeOut(duration: 100.ms),
        ),
      ],
    );
  }

  Widget _rentFree() {
    return Stack(
      alignment: Alignment.center,
      children: [
        for (int i = 0; i < 3; i++)
          Container(
            width: size * (0.38 + i * 0.16),
            height: size * (0.38 + i * 0.16),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: JarsColors.primary.withValues(alpha: 0.12 + i * 0.14),
                width: 1.5,
              ),
            ),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scale(
                duration: (850 + i * 120).ms,
                begin: const Offset(0.72, 0.72),
                end: const Offset(1.02, 1.02),
              ),
        Text('🧠', style: TextStyle(fontSize: size * 0.44)),
      ],
    );
  }
}
