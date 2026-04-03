import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/log_screen_style.dart';

/// Compact weight pill (~60 dp tall) — does NOT inflate parent row height.
/// Tapping shows a vertical drag track in an [Overlay] above the pill.
class WeightSliderPill extends StatefulWidget {
  final double weight;
  final ValueChanged<double> onWeightChanged;
  final bool enabled;

  const WeightSliderPill({
    super.key,
    required this.weight,
    required this.onWeightChanged,
    this.enabled = true,
  });

  @override
  State<WeightSliderPill> createState() => _WeightSliderPillState();
}

class _WeightSliderPillState extends State<WeightSliderPill>
    with SingleTickerProviderStateMixin {
  static const double _pillW = 52;

  final _pillKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  Timer? _collapseTimer;
  bool _expanded = false;

  late AnimationController _anim;

  /// Shared notifier so the overlay can read updated weight without rebuilding
  /// the pill itself (avoids setState-during-build).
  late final ValueNotifier<double> _weightNotifier;

  @override
  void initState() {
    super.initState();
    _weightNotifier = ValueNotifier<double>(widget.weight);
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
  }

  @override
  void didUpdateWidget(covariant WeightSliderPill old) {
    super.didUpdateWidget(old);
    // Push new weight into notifier; the overlay listens and rebuilds itself.
    if (old.weight != widget.weight) {
      _weightNotifier.value = widget.weight;
    }
  }

  @override
  void dispose() {
    _collapseTimer?.cancel();
    _removeOverlay();
    _anim.dispose();
    _weightNotifier.dispose();
    super.dispose();
  }

  void _scheduleCollapse() {
    _collapseTimer?.cancel();
    _collapseTimer = Timer(const Duration(seconds: 2), _collapse);
  }

  void _bump() {
    _collapseTimer?.cancel();
    _scheduleCollapse();
  }

  void _collapse() {
    if (!_expanded) return;
    _anim.reverse().then((_) => _removeOverlay());
    if (mounted) setState(() => _expanded = false);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  Rect? _pillRect() {
    final box = _pillKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _openOverlay() {
    _removeOverlay();
    final rect = _pillRect();
    if (rect == null) return;

    final anim = CurvedAnimation(parent: _anim, curve: Curves.easeOutCubic);

    _overlayEntry = OverlayEntry(
      builder: (_) => _WeightTrackOverlay(
        pillRect: rect,
        animation: anim,
        weightNotifier: _weightNotifier,
        onWeightChanged: (w) {
          widget.onWeightChanged(w);
          _bump();
        },
      ),
    );

    Overlay.of(context, rootOverlay: true).insert(_overlayEntry!);
  }

  void _toggle() {
    if (!widget.enabled) return;
    if (_expanded) {
      _collapse();
    } else {
      setState(() => _expanded = true);
      _openOverlay();
      _anim.forward(from: 0);
      _scheduleCollapse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return SizedBox(width: _pillW);
    final w = widget.weight;
    final hasWeight = w > 0;

    return GestureDetector(
      key: _pillKey,
      onTap: _toggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        width: _pillW,
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: _expanded
              ? kLogPurple.withValues(alpha: 0.18)
              : kLogSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: _expanded
                ? kLogPurple
                : Colors.white.withValues(alpha: 0.12),
            width: _expanded ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            hasWeight
                ? Text(
                    w % 1 == 0
                        ? w.toStringAsFixed(0)
                        : w.toStringAsFixed(1),
                    style: GoogleFonts.spaceMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: kLogGold,
                      height: 1.1,
                    ),
                  )
                : const Text('🏋️',
                    style: TextStyle(fontSize: 18, height: 1.1)),
            const SizedBox(height: 2),
            Text(
              'lbs',
              style: GoogleFonts.inter(
                fontSize: 9,
                color: Colors.white.withValues(alpha: 0.4),
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

class _WeightTrackOverlay extends StatefulWidget {
  final Rect pillRect;
  final Animation<double> animation;
  final ValueNotifier<double> weightNotifier;
  final ValueChanged<double> onWeightChanged;

  const _WeightTrackOverlay({
    required this.pillRect,
    required this.animation,
    required this.weightNotifier,
    required this.onWeightChanged,
  });

  @override
  State<_WeightTrackOverlay> createState() => _WeightTrackOverlayState();
}

class _WeightTrackOverlayState extends State<_WeightTrackOverlay> {
  static const double _trackH = 180;
  static const double _minW = 0;
  static const double _maxW = 500;

  @override
  Widget build(BuildContext context) {
    final r = widget.pillRect;
    final top = r.top - _trackH - 6;
    final left = r.left + (r.width / 2) - 30;

    return Positioned(
      left: left.clamp(8.0, double.infinity),
      top: top.clamp(8.0, double.infinity),
      width: 60,
      height: _trackH,
      child: AnimatedBuilder(
        animation: widget.animation,
        builder: (_, child) => Opacity(
          opacity: widget.animation.value,
          child: Transform.translate(
            offset: Offset(0, (1 - widget.animation.value) * 10),
            child: child,
          ),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragUpdate: (d) {
            final current = widget.weightNotifier.value;
            final delta = -d.delta.dy / (_trackH / (_maxW / 5));
            final next = (current + delta * 5).clamp(_minW, _maxW);
            final snapped = (next / 5).round() * 5.0;
            if (snapped != current) {
              HapticFeedback.selectionClick();
              widget.onWeightChanged(snapped);
            }
          },
          child: ValueListenableBuilder<double>(
            valueListenable: widget.weightNotifier,
            builder: (_, w, __) => _TrackBody(weight: w, trackH: _trackH),
          ),
        ),
      ),
    );
  }
}

class _TrackBody extends StatelessWidget {
  final double weight;
  final double trackH;

  const _TrackBody({required this.weight, required this.trackH});

  @override
  Widget build(BuildContext context) {
    const maxDisplay = 200.0;
    final fraction = (weight / maxDisplay).clamp(0.0, 1.0);

    return Container(
      decoration: BoxDecoration(
        color: kLogSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: kLogPurple.withValues(alpha: 0.35),
        ),
      ),
      clipBehavior: Clip.hardEdge,
      child: Stack(
        children: [
          // Filled bar from bottom
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: trackH * fraction,
            child: ColoredBox(
              color: kLogPurple.withValues(alpha: 0.25),
            ),
          ),
          // Center label
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  weight == 0
                      ? '—'
                      : (weight % 1 == 0
                          ? weight.toStringAsFixed(0)
                          : weight.toStringAsFixed(1)),
                  style: GoogleFonts.spaceMono(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: weight > 0 ? kLogGold : Colors.white38,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'lbs',
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: Colors.white30,
                  ),
                ),
              ],
            ),
          ),
          // Drag hint arrows
          const Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Icon(Icons.keyboard_arrow_up,
                color: Colors.white24, size: 16),
          ),
          const Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Icon(Icons.keyboard_arrow_down,
                color: Colors.white24, size: 16),
          ),
        ],
      ),
    );
  }
}
