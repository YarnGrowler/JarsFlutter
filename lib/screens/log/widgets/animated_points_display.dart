import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/log_screen_style.dart';
import '../../../core/streak_bonus.dart';

/// Digit-flip display showing "= X pts".
/// Each digit column flips independently like a slot machine / flip clock.
class AnimatedPointsDisplay extends StatefulWidget {
  final double targetPoints;
  final bool visible;

  /// When set after a successful log, shows base → streak bonus → total (staggered).
  final int? celebrationBase;
  final int? celebrationStreakBonus;
  final int? celebrationTotal;
  final int? celebrationStreakDays;

  const AnimatedPointsDisplay({
    super.key,
    required this.targetPoints,
    this.visible = true,
    this.celebrationBase,
    this.celebrationStreakBonus,
    this.celebrationTotal,
    this.celebrationStreakDays,
  });

  @override
  State<AnimatedPointsDisplay> createState() => _AnimatedPointsDisplayState();
}

class _AnimatedPointsDisplayState extends State<AnimatedPointsDisplay> {
  int _displayed = 0;
  int _target = 0;

  @override
  void initState() {
    super.initState();
    _target = widget.targetPoints.round();
    _displayed = _target;
  }

  @override
  void didUpdateWidget(covariant AnimatedPointsDisplay old) {
    super.didUpdateWidget(old);
    final newTarget = widget.targetPoints.round();
    if (newTarget != _target) {
      setState(() {
        _displayed = _target; // freeze old for flip start
        _target = newTarget;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.visible) return const SizedBox(height: 56);

    final cBase = widget.celebrationBase;
    final cStreak = widget.celebrationStreakBonus;
    final cTotal = widget.celebrationTotal;
    if (cBase != null &&
        cStreak != null &&
        cTotal != null &&
        cStreak > 0) {
      final days = widget.celebrationStreakDays ?? 1;
      final pct =
          (streakBonusFraction(days) * 100).clamp(0.0, 25.0).toDouble();
      return _LogStreakCelebration(
        base: cBase,
        streakBonus: cStreak,
        total: cTotal,
        streakPercent: pct,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          '= ',
          style: GoogleFonts.spaceMono(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: kLogGoldMuted,
            height: 1,
          ),
        ),
        _FlipNumber(
          value: _target,
          previousValue: _displayed,
        ),
        Text(
          ' pts',
          style: GoogleFonts.spaceMono(
            fontSize: 28,
            fontWeight: FontWeight.w700,
            color: kLogGoldMuted,
            height: 1,
          ),
        ),
      ],
    );
  }
}

/// Same "= … pts" row as normal log; digits flip from base → total; streak line explains the bonus.
class _LogStreakCelebration extends StatelessWidget {
  final int base;
  final int streakBonus;
  final int total;
  final double streakPercent;

  const _LogStreakCelebration({
    required this.base,
    required this.streakBonus,
    required this.total,
    required this.streakPercent,
  });

  @override
  Widget build(BuildContext context) {
    final pctLabel = streakPercent.round();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              '= ',
              style: GoogleFonts.spaceMono(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: kLogGoldMuted,
                height: 1,
              ),
            ),
            _FlipNumber(
              value: total,
              previousValue: base,
              fontSize: 36,
            ),
            Text(
              ' pts',
              style: GoogleFonts.spaceMono(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: kLogGoldMuted,
                height: 1,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '+$streakBonus streak · $pctLabel%',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: kLogPurple.withValues(alpha: 0.95),
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

/// Splits an integer into digits and animates each column independently.
class _FlipNumber extends StatefulWidget {
  final int value;
  final int previousValue;
  final double fontSize;

  const _FlipNumber({
    required this.value,
    required this.previousValue,
    this.fontSize = 48,
  });

  @override
  State<_FlipNumber> createState() => _FlipNumberState();
}

class _FlipNumberState extends State<_FlipNumber> {
  late int _prev;
  late int _curr;

  @override
  void initState() {
    super.initState();
    _prev = widget.previousValue;
    _curr = widget.value;
  }

  @override
  void didUpdateWidget(covariant _FlipNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      setState(() {
        _prev = old.value;
        _curr = widget.value;
      });
    }
  }

  List<int> _digits(int n) {
    if (n == 0) return [0];
    final d = <int>[];
    var v = n.abs();
    while (v > 0) {
      d.insert(0, v % 10);
      v ~/= 10;
    }
    return d;
  }

  @override
  Widget build(BuildContext context) {
    final currDigits = _digits(_curr);
    final prevDigits = _digits(_prev);

    // Pad prev to same length
    while (prevDigits.length < currDigits.length) {
      prevDigits.insert(0, 0);
    }

    final going = _curr >= _prev; // true = count up, false = count down

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: List.generate(currDigits.length, (i) {
        final prevD = i < prevDigits.length ? prevDigits[i] : 0;
        final currD = currDigits[i];
        // Stagger: rightmost digit flips first
        final delay = Duration(
            milliseconds:
                (currDigits.length - 1 - i) * 40);
        return _FlipDigit(
          from: prevD,
          to: currD,
          goingUp: going,
          delay: delay,
          fontSize: widget.fontSize,
        );
      }),
    );
  }
}

class _FlipDigit extends StatefulWidget {
  final int from;
  final int to;
  final bool goingUp;
  final Duration delay;
  final double fontSize;

  const _FlipDigit({
    required this.from,
    required this.to,
    required this.goingUp,
    required this.delay,
    required this.fontSize,
  });

  @override
  State<_FlipDigit> createState() => _FlipDigitState();
}

class _FlipDigitState extends State<_FlipDigit>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late int _from;
  late int _to;
  late bool _goingUp;

  @override
  void initState() {
    super.initState();
    _from = widget.from;
    _to = widget.to;
    _goingUp = widget.goingUp;
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
    );
    if (_from != _to) {
      Future.delayed(widget.delay, () {
        if (mounted) _ctrl.forward(from: 0);
      });
    }
  }

  @override
  void didUpdateWidget(covariant _FlipDigit old) {
    super.didUpdateWidget(old);
    if (old.from != widget.from || old.to != widget.to) {
      _from = widget.from;
      _to = widget.to;
      _goingUp = widget.goingUp;
      _ctrl.stop();
      if (_from != _to) {
        Future.delayed(widget.delay, () {
          if (mounted) _ctrl.forward(from: 0);
        });
      } else {
        _ctrl.value = 0;
      }
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_from == _to) {
      return _DigitText(digit: _to, fontSize: widget.fontSize);
    }

    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final t = Curves.easeInOutCubic.transform(_ctrl.value);
        // Outgoing: slides out (up if counting up, down if counting down)
        final outY = _goingUp ? -t : t;
        // Incoming: slides in from opposite direction
        final inY = _goingUp ? (1 - t) : -(1 - t);
        final h = widget.fontSize * 1.2; // approx line height

        return SizedBox(
          width: _charWidth(widget.fontSize),
          height: h,
          child: ClipRect(
            child: Stack(
              children: [
                // Outgoing digit
                Transform.translate(
                  offset: Offset(0, outY * h),
                  child: Opacity(
                    opacity: (1 - t).clamp(0.0, 1.0),
                    child: _DigitText(
                        digit: _from, fontSize: widget.fontSize),
                  ),
                ),
                // Incoming digit
                Transform.translate(
                  offset: Offset(0, inY * h),
                  child: Opacity(
                    opacity: t.clamp(0.0, 1.0),
                    child: _DigitText(
                        digit: _to, fontSize: widget.fontSize),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _charWidth(double fontSize) {
    // Space Mono is monospace: width ≈ 0.6 × fontSize
    return fontSize * 0.6;
  }
}

class _DigitText extends StatelessWidget {
  final int digit;
  final double fontSize;
  const _DigitText({required this.digit, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    return Text(
      '$digit',
      style: GoogleFonts.spaceMono(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: kLogGold,
        height: 1,
      ),
    );
  }
}
