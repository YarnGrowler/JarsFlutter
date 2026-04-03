import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/log_screen_style.dart';

/// Transparent weight control that lives inside Zone 1.
///
/// • Bottom-right corner: shows current weight (or "lbs" icon if 0).
/// • Tap: shows the full-screen translucent overlay in-place.
/// • While overlay is open: drag up/down anywhere to change weight by 5 lbs.
/// • Auto-closes after 2 s of no interaction.
class WeightSwipeOverlay extends StatefulWidget {
  final double weight;
  final ValueChanged<double> onWeightChanged;
  final bool enabled;

  const WeightSwipeOverlay({
    super.key,
    required this.weight,
    required this.onWeightChanged,
    this.enabled = true,
  });

  @override
  State<WeightSwipeOverlay> createState() => _WeightSwipeOverlayState();
}

class _WeightSwipeOverlayState extends State<WeightSwipeOverlay>
    with SingleTickerProviderStateMixin {
  bool _open = false;
  double _dragAccum = 0;

  late AnimationController _anim;
  late Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _open_() {
    if (!widget.enabled || _open) return;
    setState(() {
      _open = true;
      _dragAccum = 0;
    });
    _anim.forward(from: 0);
    _scheduleClose();
  }

  void _close() {
    if (!_open) return;
    _anim.reverse().then((_) {
      if (mounted) setState(() => _open = false);
    });
  }

  @override
  void didUpdateWidget(covariant WeightSwipeOverlay old) {
    super.didUpdateWidget(old);
  }

  // ---------- auto-close ----------
  static const _autoCloseMs = 2000;
  DateTime? _lastInteract;

  void _scheduleClose() {
    _lastInteract = DateTime.now();
    Future.delayed(const Duration(milliseconds: _autoCloseMs + 100), () {
      if (!mounted || !_open) return;
      final elapsed =
          DateTime.now().difference(_lastInteract!).inMilliseconds;
      if (elapsed >= _autoCloseMs) _close();
    });
  }

  void _bump() {
    _lastInteract = DateTime.now();
    _scheduleClose();
  }

  // ---------- drag ----------
  void _onDragUpdate(DragUpdateDetails d) {
    _dragAccum -= d.delta.dy; // up = positive
    const pxPerStep = 20.0;
    while (_dragAccum >= pxPerStep) {
      _dragAccum -= pxPerStep;
      final next = (widget.weight + 5).clamp(0.0, 999.0);
      if (next != widget.weight) {
        HapticFeedback.selectionClick();
        widget.onWeightChanged(next);
      }
    }
    while (_dragAccum <= -pxPerStep) {
      _dragAccum += pxPerStep;
      final next = (widget.weight - 5).clamp(0.0, 999.0);
      if (next != widget.weight) {
        HapticFeedback.selectionClick();
        widget.onWeightChanged(next);
      }
    }
    _bump();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) {
      return const SizedBox.shrink();
    }

    final hasWeight = widget.weight > 0;
    final label = hasWeight
        ? '${widget.weight.toStringAsFixed(widget.weight % 1 == 0 ? 0 : 1)} lbs'
        : 'lbs';

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Pill badge (always visible)
        GestureDetector(
          onTap: _open_,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _open
                  ? kLogPurple.withValues(alpha: 0.22)
                  : Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: _open
                    ? kLogPurple.withValues(alpha: 0.7)
                    : Colors.white.withValues(alpha: 0.14),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!hasWeight)
                  const Text('🏋️',
                      style: TextStyle(fontSize: 14, height: 1))
                else
                  Text(
                    widget.weight.toStringAsFixed(
                        widget.weight % 1 == 0 ? 0 : 1),
                    style: GoogleFonts.spaceMono(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kLogGold,
                      height: 1,
                    ),
                  ),
                const SizedBox(width: 4),
                Text(
                  'lbs',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: hasWeight
                        ? kLogGold.withValues(alpha: 0.6)
                        : Colors.white.withValues(alpha: 0.35),
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
        ),

        // Transparent full-zone overlay when open
        if (_open)
          Positioned.fill(
            child: FadeTransition(
              opacity: _fade,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onVerticalDragUpdate: _onDragUpdate,
                onVerticalDragEnd: (_) => _bump(),
                onTap: _close,
                child: Stack(
                  children: [
                    // Frosted label in centre of zone
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: _WeightHUD(
                            weight: widget.weight,
                            label: label,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _WeightHUD extends StatelessWidget {
  final double weight;
  final String label;

  const _WeightHUD({required this.weight, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: kLogPurple.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            weight == 0
                ? '—'
                : weight.toStringAsFixed(weight % 1 == 0 ? 0 : 1),
            style: GoogleFonts.spaceMono(
              fontSize: 52,
              fontWeight: FontWeight.w700,
              color: weight > 0 ? kLogGold : Colors.white38,
              height: 1,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'lbs',
            style: GoogleFonts.inter(
              fontSize: 14,
              color: Colors.white38,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.keyboard_arrow_up,
                  color: Colors.white38, size: 18),
              const SizedBox(width: 6),
              Text(
                'swipe up / down',
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: Colors.white38,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down,
                  color: Colors.white38, size: 18),
            ],
          ),
        ],
      ),
    );
  }
}
