import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/onboarding_campaign.dart';
import '../../core/theme.dart';

/// Value slides (S2–S4). Page 3 is interactive hold-to-log.
class ValueSlidesScreen extends StatefulWidget {
  const ValueSlidesScreen({super.key});

  @override
  State<ValueSlidesScreen> createState() => _ValueSlidesScreenState();
}

class _ValueSlidesScreenState extends State<ValueSlidesScreen> {
  final _pageCtrl = PageController();
  int _page = 0;
  static const _pageCount = 3;

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  Future<void> _goQuestions() async {
    await OnboardingCampaign.markSlidesCompleted();
    if (!mounted) return;
    context.go('/onboarding/q1');
  }

  void _next() {
    HapticFeedback.selectionClick();
    if (_page < _pageCount - 1) {
      _pageCtrl.nextPage(
        duration: const Duration(milliseconds: 340),
        curve: Curves.easeOutCubic,
      );
    } else {
      unawaited(_goQuestions());
    }
  }

  void _back() {
    HapticFeedback.selectionClick();
    if (_page > 0) {
      _pageCtrl.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      context.go('/onboarding');
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.of(context).disableAnimations;
    return Scaffold(
      backgroundColor: JarsColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 2, 6, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                    color: JarsColors.textTertiary,
                    onPressed: _back,
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(_pageCount, (i) {
                        final isActive = i == _page;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          height: 4,
                          width: isActive ? 22 : 5,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(99),
                            color: isActive
                                ? JarsColors.textPrimary.withValues(alpha: 0.45)
                                : JarsColors.border.withValues(alpha: 0.7),
                          ),
                        );
                      }),
                    ),
                  ),
                  if (_page < _pageCount - 1)
                    IconButton(
                      tooltip: 'Next',
                      onPressed: _next,
                      icon: Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: JarsColors.textPrimary.withValues(alpha: 0.85),
                      ),
                    )
                  else
                    const SizedBox(width: 44),
                ],
              ),
            ),
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: _page < _pageCount - 1 ? _next : null,
                child: PageView(
                  controller: _pageCtrl,
                  onPageChanged: (i) => setState(() => _page = i),
                  children: [
                    _SlideRoomBoard(reduceMotion: reduce),
                    _SlideRankLoop(reduceMotion: reduce),
                    _SlideHoldToLog(
                      reduceMotion: reduce,
                      onCompleted: _goQuestions,
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 16),
              child: Text(
                _page < _pageCount - 1 ? 'Swipe' : 'Hold to continue',
                textAlign: TextAlign.center,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  letterSpacing: 0.3,
                  color: JarsColors.textTertiary.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Slide 2 — minimal, centered: one idea, air, typographic weight play.
class _SlideRoomBoard extends StatelessWidget {
  const _SlideRoomBoard({required this.reduceMotion});

  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Soft radial breath — no boxes, no fake rows
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.25),
                radius: 0.95,
                colors: [
                  JarsColors.primary.withValues(alpha: 0.12),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 36),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Text(
                'ROOM',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3.2,
                  color: JarsColors.textTertiary.withValues(alpha: 0.9),
                ),
              )
                  .animate()
                  .fadeIn(duration: reduceMotion ? 1.ms : 500.ms),
              const SizedBox(height: 44),
              Text(
                'Your crew.',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 40,
                  fontWeight: FontWeight.w300,
                  height: 1.05,
                  letterSpacing: -1.2,
                  color: JarsColors.textPrimary.withValues(alpha: 0.92),
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduceMotion ? 0.ms : 90.ms,
                    duration: reduceMotion ? 1.ms : 520.ms,
                    curve: Curves.easeOut,
                  )
                  .slideY(
                    begin: reduceMotion ? 0 : 0.03,
                    delay: 90.ms,
                    duration: 520.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 4),
              Text(
                'One leaderboard.',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 40,
                  fontWeight: FontWeight.w700,
                  height: 1.05,
                  letterSpacing: -1.0,
                  color: JarsColors.textPrimary,
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduceMotion ? 0.ms : 160.ms,
                    duration: reduceMotion ? 1.ms : 520.ms,
                  )
                  .slideY(
                    begin: reduceMotion ? 0 : 0.03,
                    delay: 160.ms,
                    duration: 520.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 36),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 300),
                child: Text(
                  'Every log lands in the same feed. '
                  'Same points. Same order. No screenshots.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    height: 1.55,
                    fontWeight: FontWeight.w400,
                    color: JarsColors.textSecondary,
                  ),
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduceMotion ? 0.ms : 260.ms,
                    duration: reduceMotion ? 1.ms : 480.ms,
                  ),
              const SizedBox(height: 56),
              // Single hairline — vertical gradient, not a UI chrome
              Container(
                width: 1,
                height: 72,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(99),
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      JarsColors.primary.withValues(alpha: 0.55),
                      Colors.transparent,
                    ],
                  ),
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduceMotion ? 0.ms : 340.ms,
                    duration: reduceMotion ? 1.ms : 600.ms,
                  )
                  .scale(
                    begin: const Offset(1, 0.2),
                    end: const Offset(1, 1),
                    delay: 340.ms,
                    duration: 600.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ],
    );
  }
}

/// Slide 3 — different rhythm: asymmetric, right-weighted, one quiet arc.
class _SlideRankLoop extends StatelessWidget {
  const _SlideRankLoop({required this.reduceMotion});

  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 220,
          child: IgnorePointer(
            child: CustomPaint(
              painter: _MinimalArcPainter(
                color: JarsColors.gold.withValues(alpha: 0.22),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(32, 8, 36, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Spacer(flex: 2),
              Text(
                'PRESSURE',
                style: GoogleFonts.inter(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 3.0,
                  color: JarsColors.textTertiary.withValues(alpha: 0.85),
                ),
              )
                  .animate()
                  .fadeIn(duration: reduceMotion ? 1.ms : 480.ms),
              const SizedBox(height: 44),
              Text(
                'Streaks.',
                textAlign: TextAlign.right,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 44,
                  fontWeight: FontWeight.w300,
                  height: 1.05,
                  letterSpacing: -1.4,
                  color: JarsColors.textPrimary.withValues(alpha: 0.88),
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduceMotion ? 0.ms : 80.ms,
                    duration: reduceMotion ? 1.ms : 520.ms,
                  )
                  .slideX(
                    begin: reduceMotion ? 0 : 0.04,
                    delay: 80.ms,
                    duration: 520.ms,
                    curve: Curves.easeOutCubic,
                  ),
              Text(
                'Ranks.',
                textAlign: TextAlign.right,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 44,
                  fontWeight: FontWeight.w600,
                  height: 1.05,
                  letterSpacing: -1.2,
                  color: JarsColors.textPrimary,
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduceMotion ? 0.ms : 160.ms,
                    duration: reduceMotion ? 1.ms : 520.ms,
                  )
                  .slideX(
                    begin: reduceMotion ? 0 : 0.04,
                    delay: 160.ms,
                    duration: 520.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 8),
              Text(
                'Receipts.',
                textAlign: TextAlign.right,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                  height: 1.05,
                  letterSpacing: -1.0,
                  color: JarsColors.gold.withValues(alpha: 0.95),
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduceMotion ? 0.ms : 240.ms,
                    duration: reduceMotion ? 1.ms : 520.ms,
                  )
                  .slideX(
                    begin: reduceMotion ? 0 : 0.04,
                    delay: 240.ms,
                    duration: 520.ms,
                    curve: Curves.easeOutCubic,
                  ),
              const SizedBox(height: 40),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 280),
                child: Text(
                  'Miss a day, climb back, or get passed — '
                  'the room stays honest.',
                  textAlign: TextAlign.right,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    height: 1.55,
                    fontWeight: FontWeight.w400,
                    color: JarsColors.textSecondary,
                  ),
                ),
              )
                  .animate()
                  .fadeIn(
                    delay: reduceMotion ? 0.ms : 320.ms,
                    duration: reduceMotion ? 1.ms : 480.ms,
                  ),
              const Spacer(flex: 3),
            ],
          ),
        ),
      ],
    );
  }
}

/// Whisper-thin arc at the bottom — atmosphere, not a chart.
class _MinimalArcPainter extends CustomPainter {
  _MinimalArcPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final w = size.width;
    final rect = Rect.fromCenter(
      center: Offset(w * 0.5, size.height * 1.08),
      width: w * 1.35,
      height: w * 0.55,
    );
    canvas.drawArc(
      rect,
      math.pi * 1.05,
      math.pi * 0.9,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _MinimalArcPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Slide 4 — interactive like the real Log screen:
/// - slot machine spins on entry and lands on a random exercise
/// - press & hold anywhere: ring fills at finger, purple flood expands from finger
/// - confetti burst, then advance.
class _SlideHoldToLog extends StatefulWidget {
  const _SlideHoldToLog({
    required this.reduceMotion,
    required this.onCompleted,
  });

  final bool reduceMotion;
  final Future<void> Function() onCompleted;

  @override
  State<_SlideHoldToLog> createState() => _SlideHoldToLogState();
}

class _SlideHoldToLogState extends State<_SlideHoldToLog>
    with TickerProviderStateMixin {
  static const _holdDuration = Duration(seconds: 2);
  static const _repsRollDuration = Duration(milliseconds: 920);

  static const _options = <({String label, IconData icon})>[
    (label: 'Pull-ups', icon: Icons.sports_martial_arts_rounded),
    (label: 'Push-ups', icon: Icons.fitness_center_rounded),
    (label: 'Squats', icon: Icons.bolt_rounded),
    (label: 'Run', icon: Icons.directions_run_rounded),
    (label: 'Plank', icon: Icons.timer_outlined),
    (label: 'Burpees', icon: Icons.flash_on_rounded),
  ];

  late final AnimationController _holdCtrl;
  late final AnimationController _confettiCtrl;

  int _index = 0;
  int _reps = 0;
  int _repsFinal = 12;

  bool _revealed = false; // copy + reps appear

  bool _holding = false;
  bool _sustainingFlood = false;
  Offset? _holdOriginGlobal;
  Offset? _sustainOriginGlobal;

  bool _completed = false;

  @override
  void initState() {
    super.initState();
    _holdCtrl = AnimationController(vsync: this, duration: _holdDuration);
    _confettiCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    _holdCtrl.addListener(() {
      // Hold ring + flood will repaint via AnimatedBuilder.
      if (!mounted) return;
      if (_holding) setState(() {});
    });

    _holdCtrl.addStatusListener((s) {
      if (s == AnimationStatus.completed && !_completed) {
        _completed = true;
        _holding = false;
        _sustainingFlood = true;
        _sustainOriginGlobal = _holdOriginGlobal;
        HapticFeedback.mediumImpact();
        _confettiCtrl.forward(from: 0);
        Future<void>.delayed(const Duration(milliseconds: 280), () async {
          if (!mounted) return;
          await widget.onCompleted();
        });
      }
    });

    // Default: pick a random bodyweight exercise and start the reps roll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final r = math.Random(DateTime.now().millisecondsSinceEpoch ^ 0xB00D1E);
      _index = r.nextInt(_options.length);
      setState(() => _revealed = true);
      _startRepsRoll();
    });
  }

  @override
  void dispose() {
    _holdCtrl.dispose();
    _confettiCtrl.dispose();
    super.dispose();
  }

  void _startRepsRoll() {
    if (widget.reduceMotion) {
      _repsFinal = 28;
      _reps = _repsFinal;
      if (mounted) setState(() {});
      return;
    }
    final r = math.Random(DateTime.now().millisecondsSinceEpoch ^ 0xD11CE);
    _repsFinal = 21 + r.nextInt(50); // 21..70
    _reps = 0;
    if (mounted) setState(() {});

    final start = DateTime.now().millisecondsSinceEpoch;
    void tick() {
      if (!mounted) return;
      final elapsed = DateTime.now().millisecondsSinceEpoch - start;
      final t = (elapsed / _repsRollDuration.inMilliseconds).clamp(0.0, 1.0);
      final eased = Curves.easeOutCubic.transform(t);
      final next = (_repsFinal * eased).round().clamp(0, _repsFinal);
      if (next != _reps) setState(() => _reps = next);
      if (t < 1.0) {
        Future<void>.delayed(const Duration(milliseconds: 16), tick);
      } else {
        HapticFeedback.selectionClick();
      }
    }

    tick();
  }

  void _onPointerDown(PointerDownEvent e) {
    if (_completed) return;
    _holding = true;
    _holdOriginGlobal = e.position;
    HapticFeedback.selectionClick();
    _holdCtrl.forward(from: 0);
    setState(() {});
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_holding || _completed) return;
    _holdOriginGlobal = e.position;
    setState(() {});
  }

  void _onPointerUp(PointerUpEvent e) {
    _cancelHold();
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _cancelHold();
  }

  void _cancelHold() {
    if (_completed) return;
    _holding = false;
    _holdCtrl.reverse();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final reduce = widget.reduceMotion;
    final holdProgress = reduce ? 0.0 : _holdCtrl.value;
    final showFlood = (_holding && holdProgress > 0) || _sustainingFlood;
    final floodProgress = _sustainingFlood ? 1.0 : holdProgress;
    final floodOrigin = _sustainingFlood ? _sustainOriginGlobal : _holdOriginGlobal;

    final picked = _options[_index];
    final secondsLeft = _holding
        ? (_holdDuration.inSeconds * (1 - holdProgress)).ceil().clamp(0, 99)
        : 0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // Interaction surface (like Log screen).
        Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: _onPointerUp,
          onPointerCancel: _onPointerCancel,
          child: const SizedBox.expand(),
        ),

        // Flood overlay (radial, from finger) — must be BEHIND text/number.
        if (showFlood && floodOrigin != null)
          Positioned.fill(
            child: IgnorePointer(
              child: _FloodOverlay(
                progress: floodProgress,
                originGlobal: floodOrigin,
              ),
            ),
          ),

        if (_revealed)
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                const Spacer(flex: 2),
                Text(
                  'LOG',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 3.2,
                    color: JarsColors.textTertiary.withValues(alpha: 0.9),
                  ),
                )
                    .animate()
                    .fadeIn(duration: reduce ? 1.ms : 420.ms),
                const SizedBox(height: 22),
                Text(
                  'Log your reps.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 44,
                    fontWeight: FontWeight.w700,
                    height: 1.04,
                    letterSpacing: -1.2,
                    color: JarsColors.textPrimary,
                  ),
                )
                    .animate()
                    .fadeIn(duration: reduce ? 1.ms : 520.ms)
                    .slideY(
                      begin: reduce ? 0 : 0.03,
                      duration: 520.ms,
                      curve: Curves.easeOutCubic,
                    ),
                const SizedBox(height: 18),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Text(
                    _completed
                        ? 'Locked.'
                        : _holding
                            ? '$secondsLeft more second${secondsLeft == 1 ? '' : 's'}'
                            : 'Hold anywhere to lock it in.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      height: 1.55,
                      color: JarsColors.textSecondary,
                    ),
                  ),
                )
                    .animate()
                    .fadeIn(
                      delay: reduce ? 0.ms : 120.ms,
                      duration: reduce ? 1.ms : 420.ms,
                    ),
                const SizedBox(height: 44),
                // Centered "exercise + reps" block (text stays above flood).
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: JarsColors.surface.withValues(alpha: 0.92),
                        border: Border.all(
                          color: JarsColors.border.withValues(alpha: 0.9),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            picked.icon,
                            size: 20,
                            color: _completed
                                ? JarsColors.gold
                                : JarsColors.primary.withValues(alpha: 0.9),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            picked.label,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: JarsColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    )
                        .animate()
                        .scale(
                          begin: const Offset(0.98, 0.98),
                          end: const Offset(1, 1),
                          duration: reduce ? 1.ms : 220.ms,
                          curve: Curves.easeOutCubic,
                        ),
                    const SizedBox(height: 18),
                    // Reps number + ring (centered around number).
                    SizedBox(
                      width: 210,
                      height: 210,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if ((_holding || _sustainingFlood) &&
                              holdProgress > 0)
                            RepaintBoundary(
                              child: CustomPaint(
                                painter:
                                    _HoldRingPainter(progress: holdProgress),
                              ),
                            ),
                          Center(
                            child: _VerticalRollingNumber(
                              value: _reps,
                              color: Colors.white.withValues(
                                alpha: (_holding || _sustainingFlood)
                                    ? 0.98
                                    : 0.9,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'reps',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        letterSpacing: 2.2,
                        color: JarsColors.textTertiary.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
                const Spacer(flex: 3),
              ],
            ),
          ),

        // Confetti burst on completion.
        if (_completed && _sustainOriginGlobal != null)
          Positioned.fill(
            child: IgnorePointer(
              child: _ConfettiBurst(
                progress: _confettiCtrl,
                originGlobal: _sustainOriginGlobal!,
              ),
            ),
          ),
      ],
    );
  }
}

class _FloodOverlay extends StatelessWidget {
  final double progress;
  final Offset originGlobal;

  const _FloodOverlay({required this.progress, required this.originGlobal});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final box = ctx.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.globalToLocal(originGlobal)
          : Offset(c.maxWidth / 2, c.maxHeight / 2);

      double maxR = 0;
      for (final corner in [
        Offset.zero,
        Offset(c.maxWidth, 0),
        Offset(0, c.maxHeight),
        Offset(c.maxWidth, c.maxHeight),
      ]) {
        final d = (corner - origin).distance;
        if (d > maxR) maxR = d;
      }

      final eased = Curves.easeInCubic.transform(progress);
      final radius = maxR * eased;

      return CustomPaint(
        size: Size(c.maxWidth, c.maxHeight),
        painter: _FloodPainter(origin: origin, radius: radius),
      );
    });
  }
}

class _FloodPainter extends CustomPainter {
  final Offset origin;
  final double radius;

  _FloodPainter({required this.origin, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    if (radius <= 0) return;
    final path = Path()
      ..addOval(Rect.fromCircle(center: origin, radius: radius));
    canvas.save();
    canvas.clipPath(path);
    final rect = Rect.fromLTWH(0, 0, size.width, size.height);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = RadialGradient(
          center: Alignment(
            (origin.dx / size.width) * 2 - 1,
            (origin.dy / size.height) * 2 - 1,
          ),
          radius: 1.0,
          colors: const [
            Color(0xDD9B8FFF),
            Color(0xCC7C6FFF),
            Color(0xBB4A3FCC),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(rect),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FloodPainter old) =>
      old.radius != radius || old.origin != origin;
}

class _HoldRingPainter extends CustomPainter {
  final double progress;
  _HoldRingPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const r = 64.0;
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.10)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: r),
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.92)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _HoldRingPainter old) =>
      old.progress != progress;
}

class _ConfettiBurst extends StatelessWidget {
  const _ConfettiBurst({required this.progress, required this.originGlobal});

  final Animation<double> progress;
  final Offset originGlobal;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, c) {
      final box = ctx.findRenderObject() as RenderBox?;
      final origin = box != null
          ? box.globalToLocal(originGlobal)
          : Offset(c.maxWidth / 2, c.maxHeight / 2);
      return CustomPaint(
        size: Size(c.maxWidth, c.maxHeight),
        painter: _ConfettiPainter(origin: origin, t: progress.value),
      );
    });
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter({required this.origin, required this.t});

  final Offset origin;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final r = math.Random(origin.dx.toInt() ^ (origin.dy.toInt() << 6));
    final colors = [
      JarsColors.gold,
      Colors.white,
      JarsColors.primary,
      JarsColors.primary.withValues(alpha: 0.7),
    ];

    final eased = Curves.easeOutCubic.transform(t);
    final fade = (1 - Curves.easeIn.transform(t)).clamp(0.0, 1.0);

    for (var i = 0; i < 28; i++) {
      final a = (i / 28) * math.pi * 2 + (r.nextDouble() - 0.5) * 0.22;
      final dist = 22 + eased * (140 + r.nextDouble() * 80);
      final dx = math.cos(a) * dist;
      final dy = math.sin(a) * dist - eased * (40 + r.nextDouble() * 30);
      final p = origin + Offset(dx, dy);
      final w = 4 + r.nextDouble() * 5;
      final h = 2 + r.nextDouble() * 5;
      final paint = Paint()
        ..color = colors[i % colors.length].withValues(alpha: 0.9 * fade);
      canvas.save();
      canvas.translate(p.dx, p.dy);
      canvas.rotate(a + eased * 2.2);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset.zero, width: w, height: h),
          const Radius.circular(1.2),
        ),
        paint,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.origin != origin;
}

/// Minimal odometer-like number: each value slides up as it increments.
class _VerticalRollingNumber extends StatelessWidget {
  const _VerticalRollingNumber({
    required this.value,
    required this.color,
  });

  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 140),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, anim) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.18),
          end: Offset.zero,
        ).animate(anim);
        final fade = Tween<double>(begin: 0.0, end: 1.0).animate(anim);
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: Text(
        '$value',
        key: ValueKey<int>(value),
        style: GoogleFonts.spaceMono(
          fontSize: 88,
          fontWeight: FontWeight.w700,
          height: 1,
          color: color,
        ),
      ),
    );
  }
}
