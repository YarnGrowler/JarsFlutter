import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/log_screen_style.dart';
import '../../models/level.dart';
import 'widgets/share_rank_story.dart';

/// Full-screen rank-up sequence (~2.5s min before dismiss / share).
class RankUpCeremonyScreen extends StatefulWidget {
  final Level previousLevel;
  final Level newLevel;
  final String username;
  final double totalPoints;
  final double previousThreshold;

  const RankUpCeremonyScreen({
    super.key,
    required this.previousLevel,
    required this.newLevel,
    required this.username,
    required this.totalPoints,
    required this.previousThreshold,
  });

  @override
  State<RankUpCeremonyScreen> createState() => _RankUpCeremonyScreenState();
}

class _RankUpCeremonyScreenState extends State<RankUpCeremonyScreen>
    with TickerProviderStateMixin {
  final _shareKey = GlobalKey();

  late AnimationController _irisClose;
  late AnimationController _oldBadge;
  late AnimationController _newBadge;
  late AnimationController _pulse;
  late AnimationController _type;
  late AnimationController _quoteFade;
  late AnimationController _points;
  late AnimationController _shareSlide;

  String _typed = '';
  bool _canDismiss = false;
  bool _showShare = false;
  late Animation<double> _pointsTween;

  @override
  void initState() {
    super.initState();
    _irisClose = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _oldBadge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _newBadge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
    _type = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: math.max(1, widget.newLevel.title.length * 60),
      ),
    );
    _quoteFade = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
    _points = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _pointsTween = Tween<double>(
      begin: widget.previousThreshold,
      end: widget.totalPoints,
    ).animate(CurvedAnimation(parent: _points, curve: Curves.easeOutCubic));

    _shareSlide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );

    _irisClose.value = 1.0;
    _type.addListener(_onTypeTick);
    _sequence();
  }

  Future<void> _sequence() async {
    await _irisClose.reverse();
    if (!mounted) return;

    await _oldBadge.forward();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    _newBadge.forward();
    HapticFeedback.heavyImpact();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted) return;

    await _type.forward();
    setState(() => _typed = widget.newLevel.title);

    await _quoteFade.forward();
    await _points.forward();

    await Future<void>.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    setState(() => _canDismiss = true);

    await Future<void>.delayed(const Duration(milliseconds: 1600));
    if (!mounted) return;
    setState(() => _showShare = true);
    _shareSlide.forward();
  }

  void _onTypeTick() {
    final n = widget.newLevel.title.length;
    final i = (n * _type.value).floor().clamp(0, n);
    setState(() => _typed = widget.newLevel.title.substring(0, i));
  }

  @override
  void dispose() {
    _type.removeListener(_onTypeTick);
    _irisClose.dispose();
    _oldBadge.dispose();
    _newBadge.dispose();
    _pulse.dispose();
    _type.dispose();
    _quoteFade.dispose();
    _points.dispose();
    _shareSlide.dispose();
    super.dispose();
  }

  Future<void> _share() async {
    try {
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
      if (!mounted) return;
      final boundary =
          _shareKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) return;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      if (bytes == null) return;
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/jars_rank_story.png');
      await file.writeAsBytes(bytes.buffer.asUint8List());
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        text: '${widget.username} — ${widget.newLevel.title}',
      );
    } catch (_) {}
  }

  Future<void> _dismiss() async {
    if (!_canDismiss) return;
    await _irisClose.forward();
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final sz = MediaQuery.sizeOf(context);
    final rankColor = widget.newLevel.color;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _dismiss,
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: rankColor.withValues(alpha: 0.12),
                ),
              ),
            ),
            Center(
              child: AnimatedBuilder(
                animation: Listenable.merge([_oldBadge, _newBadge, _pulse]),
                builder: (_, __) {
                  final oldT = _oldBadge.value;
                  if (oldT < 1.0 && _newBadge.value < 0.01) {
                    final shake = math.sin(oldT * math.pi * 4) * 10 * (1 - oldT);
                    return Transform.translate(
                      offset: Offset(shake, 0),
                      child: Opacity(
                        opacity: 1 - oldT,
                        child: _rankCircle(widget.previousLevel, 120),
                      ),
                    );
                  }
                  final drop = CurvedAnimation(
                    parent: _newBadge,
                    curve: Curves.elasticOut,
                  ).value;
                  final scale = 1.35 - drop * 0.25;
                  final pulseS =
                      1.0 + 0.04 * math.sin(_pulse.value * math.pi * 2);
                  return Transform.scale(
                    scale: scale * pulseS,
                    child: _rankCircle(widget.newLevel, 140),
                  );
                },
              ),
            ),
            Positioned(
              left: 24,
              right: 24,
              bottom: sz.height * 0.22,
              child: Column(
                children: [
                  Text(
                    _typed,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: rankColor,
                    ),
                  ),
                  const SizedBox(height: 12),
                  FadeTransition(
                    opacity: _quoteFade,
                    child: Text(
                      widget.newLevel.description,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 16,
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.italic,
                        color: kLogText.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  AnimatedBuilder(
                    animation: _pointsTween,
                    builder: (_, __) {
                      final v = _pointsTween.value;
                      final txt =
                          v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
                      return Text(
                        '$txt pts',
                        style: GoogleFonts.spaceMono(
                          fontSize: 24,
                          fontWeight: FontWeight.w700,
                          color: kLogGold,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            if (_showShare)
              Positioned(
                left: 24,
                right: 24,
                bottom: 48,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, 1.2),
                    end: Offset.zero,
                  ).animate(CurvedAnimation(parent: _shareSlide, curve: Curves.easeOutCubic)),
                  child: Center(
                    child: Material(
                      color: kLogSurface,
                      borderRadius: BorderRadius.circular(999),
                      child: InkWell(
                        onTap: _share,
                        borderRadius: BorderRadius.circular(999),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 14,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.share_rounded, color: Colors.white, size: 18),
                              const SizedBox(width: 10),
                              Text(
                                'Share your rank',
                                style: GoogleFonts.spaceGrotesk(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              left: -3000,
              child: RepaintBoundary(
                key: _shareKey,
                child: SizedBox(
                  width: 1080,
                  height: 1920,
                  child: ShareRankStory(
                    level: widget.newLevel,
                    username: widget.username,
                    totalPoints: widget.totalPoints,
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _irisClose,
                builder: (_, __) {
                  return CustomPaint(
                    painter: _IrisBlackPainter(progress: _irisClose.value),
                    size: sz,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _rankCircle(Level level, double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: level.color.withValues(alpha: 0.2),
        border: Border.all(color: level.color, width: 3),
        boxShadow: [
          BoxShadow(
            color: level.color.withValues(alpha: 0.35),
            blurRadius: 24,
          ),
        ],
      ),
      child: Center(
        child: Text(level.icon, style: TextStyle(fontSize: size * 0.45)),
      ),
    );
  }
}

class _IrisBlackPainter extends CustomPainter {
  final double progress;

  _IrisBlackPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final maxR = math.sqrt(size.width * size.width + size.height * size.height);
    final r = maxR * progress;
    final paint = Paint()..color = Colors.black;
    canvas.drawCircle(c, r, paint);
  }

  @override
  bool shouldRepaint(covariant _IrisBlackPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
