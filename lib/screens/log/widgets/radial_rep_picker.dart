import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/log_screen_style.dart';

/// Premium rep-count picker.
///
/// Design:
///   • Full-screen dark scrim
///   • Bottom sheet (slides up) with frosted dark background
///   • Giant rep number in the center
///   • Drag UP or DOWN on the number to change value smoothly
///   • Tap − / + buttons on either side for ±1
///   • Long-press − / + for rapid ±5
///   • Quick preset chips (+5, +10, +20, +50) below the number
///   • "Set X reps" confirm pill at the bottom
///
/// Opened via showGeneralDialog (no Navigator route) so it works
/// as an overlay without a new route.
class RadialRepPicker extends StatefulWidget {
  final int initialValue;
  final ValueChanged<int> onClose;

  const RadialRepPicker({
    super.key,
    required this.initialValue,
    required this.onClose,
  });

  @override
  State<RadialRepPicker> createState() => _RadialRepPickerState();
}

class _RadialRepPickerState extends State<RadialRepPicker>
    with TickerProviderStateMixin {
  static const _maxVal = 999;
  static const _minVal = 0;

  // Rep count
  late int _value;

  // Drag state
  double _dragAccum = 0;

  // Rapid-fire from long-pressing +/-
  Timer? _rapidTimer;

  // Animations
  late AnimationController _sheetAnim;
  late Animation<Offset> _sheetSlide;
  late AnimationController _bumpAnim;
  bool _closing = false;

  // Tracks last value for bump direction
  int _prevValue = 0;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue.clamp(_minVal, _maxVal);
    _prevValue = _value;

    _sheetAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _sheetSlide = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _sheetAnim, curve: Curves.easeOutCubic));
    _sheetAnim.forward();

    _bumpAnim = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 150))
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _bumpAnim.reverse();
      });
  }

  @override
  void dispose() {
    _rapidTimer?.cancel();
    _sheetAnim.dispose();
    _bumpAnim.dispose();
    super.dispose();
  }

  void _dismiss({int? value}) {
    if (_closing) return;
    _closing = true;
    _rapidTimer?.cancel();
    _sheetAnim.reverse().then((_) {
      if (mounted) widget.onClose(value ?? _value);
    });
  }

  void _set(int newVal, {bool haptic = true}) {
    final clamped = newVal.clamp(_minVal, _maxVal);
    if (clamped == _value) return;
    if (haptic) HapticFeedback.selectionClick();
    setState(() {
      _prevValue = _value;
      _value = clamped;
    });
    _bumpAnim.forward(from: 0);
  }

  void _startRapid(int delta) {
    _rapidTimer?.cancel();
    _rapidTimer = Timer.periodic(const Duration(milliseconds: 80), (_) {
      _set(_value + delta);
    });
  }

  void _stopRapid() {
    _rapidTimer?.cancel();
    _rapidTimer = null;
  }

  // ── Drag on the big number ─────────────────────────────────────────────────
  void _onDragUpdate(DragUpdateDetails d) {
    // 10 px vertical drag = 1 rep
    _dragAccum -= d.delta.dy;
    final steps = _dragAccum ~/ 10;
    if (steps != 0) {
      _dragAccum -= steps * 10;
      _set(_value + steps, haptic: false);
      if (steps != 0) HapticFeedback.selectionClick();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final sheetH = screenH * 0.55;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Dark scrim (tap to dismiss)
          Positioned.fill(
            child: GestureDetector(
              onTap: _dismiss,
              child: AnimatedBuilder(
                animation: _sheetAnim,
                builder: (_, __) => ColoredBox(
                  color: Colors.black
                      .withValues(alpha: 0.75 * _sheetAnim.value),
                ),
              ),
            ),
          ),

          // Bottom sheet
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SlideTransition(
              position: _sheetSlide,
              child: GestureDetector(
                // Prevent scrim tap from propagating
                onTap: () {},
                child: Container(
                  height: sheetH,
                  decoration: const BoxDecoration(
                    color: Color(0xFF111118),
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(28)),
                  ),
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
                      child: Column(
                        children: [
                          // Drag handle
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),

                          const SizedBox(height: 12),

                          // Label
                          Text(
                            'REPS',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 3.5,
                              color: kLogPurple.withValues(alpha: 0.75),
                            ),
                          ),

                          const SizedBox(height: 16),

                          // ─── Core row: − | BIG NUMBER | + ──────────────────
                          Expanded(
                            child: Row(
                              children: [
                                // Minus
                                _SideButton(
                                  icon: Icons.remove_rounded,
                                  onTap: () => _set(_value - 1),
                                  onLongPressStart: () => _startRapid(-1),
                                  onLongPressEnd: _stopRapid,
                                ),

                                // Big number (drag-sensitive)
                                Expanded(
                                  child: GestureDetector(
                                    onVerticalDragUpdate: _onDragUpdate,
                                    child: Center(
                                      child: AnimatedBuilder(
                                        animation: _bumpAnim,
                                        builder: (_, __) {
                                          final going = _value >= _prevValue;
                                          final t = _bumpAnim.value;
                                          // Slight bounce-up or bounce-down
                                          final dy = going
                                              ? -8 * t * (1 - t) * 4
                                              : 8 * t * (1 - t) * 4;
                                          return Transform.translate(
                                            offset: Offset(0, dy),
                                            child: Text(
                                              '$_value',
                                              style: GoogleFonts.spaceMono(
                                                fontSize: 100,
                                                fontWeight: FontWeight.w700,
                                                color: Colors.white,
                                                height: 1,
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),

                                // Plus
                                _SideButton(
                                  icon: Icons.add_rounded,
                                  onTap: () => _set(_value + 1),
                                  onLongPressStart: () => _startRapid(1),
                                  onLongPressEnd: _stopRapid,
                                ),
                              ],
                            ),
                          ),

                          // Drag hint
                          Text(
                            'drag up/down to scroll',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: Colors.white.withValues(alpha: 0.17),
                            ),
                          ),

                          const SizedBox(height: 14),

                          // Quick presets
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [5, 10, 20, 50].map((preset) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5),
                                child: _PresetChip(
                                  label: '+$preset',
                                  onTap: () => _set(_value + preset),
                                ),
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 18),

                          // Confirm button
                          GestureDetector(
                            onTap: _dismiss,
                            child: Container(
                              height: 56,
                              decoration: BoxDecoration(
                                color: kLogPurple,
                                borderRadius: BorderRadius.circular(16),
                                boxShadow: [
                                  BoxShadow(
                                    color: kLogPurple.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    spreadRadius: -4,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  'Set $_value reps',
                                  style: GoogleFonts.spaceGrotesk(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Side +/- button
// ─────────────────────────────────────────────────────────────────────────────

class _SideButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final VoidCallback onLongPressStart;
  final VoidCallback onLongPressEnd;

  const _SideButton({
    required this.icon,
    required this.onTap,
    required this.onLongPressStart,
    required this.onLongPressEnd,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPressStart: (_) {
        HapticFeedback.mediumImpact();
        onLongPressStart();
      },
      onLongPressEnd: (_) => onLongPressEnd(),
      onLongPressCancel: onLongPressEnd,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
        ),
        child: Icon(icon, color: Colors.white, size: 32),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Quick-add preset chip
// ─────────────────────────────────────────────────────────────────────────────

class _PresetChip extends StatefulWidget {
  final String label;
  final VoidCallback onTap;

  const _PresetChip({required this.label, required this.onTap});

  @override
  State<_PresetChip> createState() => _PresetChipState();
}

class _PresetChipState extends State<_PresetChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _press;

  @override
  void initState() {
    super.initState();
    _press = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 80));
  }

  @override
  void dispose() {
    _press.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _press.forward(from: 0),
      onTapUp: (_) {
        _press.reverse();
        widget.onTap();
        HapticFeedback.selectionClick();
      },
      onTapCancel: () => _press.reverse(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, __) => Transform.scale(
          scale: 1.0 - 0.07 * _press.value,
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            decoration: BoxDecoration(
              color: Color.lerp(
                kLogSurface,
                kLogPurple.withValues(alpha: 0.35),
                _press.value,
              ),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: kLogPurple.withValues(alpha: 0.3)),
            ),
            child: Text(
              widget.label,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.white.withValues(alpha: 0.8),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
