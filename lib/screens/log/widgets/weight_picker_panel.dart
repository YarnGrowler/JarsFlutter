import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/log_screen_style.dart';

/// Full-screen iOS-style weight picker.
///
/// Layout:
///   • Frosted/dark full-screen overlay
///   • Giant live weight display at top (e.g.  "135 lbs")
///   • iOS drum-wheel in the center
///   • 3-col number pad at the bottom with backspace + decimal
///   • "Set Weight" confirm button
///
/// The number pad drives _typed input (exact values).
/// The drum wheel shows 0–500 in 1 lb increments (auto-syncs to typed value).
Future<void> showWeightPicker({
  required BuildContext context,
  required double initial,
  required ValueChanged<double> onConfirm,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'weight',
    barrierColor: Colors.transparent,
    pageBuilder: (ctx, anim, _) => _WeightPickerPage(
      initial: initial,
      onConfirm: onConfirm,
    ),
    transitionBuilder: (ctx, anim, _, child) {
      final t = Curves.easeOutCubic.transform(anim.value);
      return FadeTransition(
        opacity: anim,
        child: Transform.translate(
          offset: Offset(0, 40 * (1 - t)),
          child: child,
        ),
      );
    },
    transitionDuration: const Duration(milliseconds: 320),
  );
}

class WeightPickerPanel extends StatelessWidget {
  final double weight;
  final ValueChanged<double> onChanged;
  final VoidCallback onDismiss;

  const WeightPickerPanel({
    super.key,
    required this.weight,
    required this.onChanged,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    // This thin wrapper keeps backward compatibility with log_sheet.dart.
    // It immediately opens the full-screen picker and dismisses itself.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      showWeightPicker(
        context: context,
        initial: weight,
        onConfirm: (w) {
          onChanged(w);
          onDismiss();
        },
      );
    });
    return const SizedBox.shrink();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Full-screen picker page
// ─────────────────────────────────────────────────────────────────────────────

class _WeightPickerPage extends StatefulWidget {
  final double initial;
  final ValueChanged<double> onConfirm;

  const _WeightPickerPage({required this.initial, required this.onConfirm});

  @override
  State<_WeightPickerPage> createState() => _WeightPickerPageState();
}

class _WeightPickerPageState extends State<_WeightPickerPage> {
  static const _maxW = 999.0;
  static const _itemH = 72.0;
  static const _visibleItems = 5;

  late FixedExtentScrollController _scroll;
  // Typed string (digits + optional decimal)
  String _typed = '';
  bool _hasDecimal = false;

  double get _value {
    final d = double.tryParse(_typed.isEmpty ? '0' : _typed) ?? 0;
    return d.clamp(0, _maxW);
  }

  @override
  void initState() {
    super.initState();
    final init = widget.initial.clamp(0.0, _maxW);
    final rounded = init.round();
    _scroll = FixedExtentScrollController(initialItem: rounded);
    if (init > 0) {
      _typed = init % 1 == 0 ? init.toInt().toString() : init.toString();
      _hasDecimal = _typed.contains('.');
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _wheelChanged(int i) {
    HapticFeedback.selectionClick();
    setState(() {
      _typed = i.toString();
      _hasDecimal = false;
    });
  }

  void _numPad(String key) {
    HapticFeedback.lightImpact();
    setState(() {
      if (key == '⌫') {
        if (_typed.isEmpty) return;
        final removed = _typed[_typed.length - 1];
        _typed = _typed.substring(0, _typed.length - 1);
        if (removed == '.') _hasDecimal = false;
      } else if (key == '.') {
        if (_hasDecimal) return;
        _hasDecimal = true;
        _typed = '${_typed.isEmpty ? '0' : _typed}.';
      } else {
        // Prevent absurd values
        if (_value >= _maxW && key != '0') return;
        // Max 1 decimal digit
        if (_hasDecimal) {
          final parts = _typed.split('.');
          if (parts.length == 2 && parts[1].length >= 1) return;
        }
        _typed += key;
        // Remove leading zeros
        final d = double.tryParse(_typed);
        if (d != null && _typed.startsWith('0') && !_typed.startsWith('0.')) {
          _typed = d.toInt().toString();
        }
      }
    });
    // Sync wheel
    final idx = _value.round().clamp(0, _maxW.toInt());
    _scroll.animateToItem(
      idx,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  void _confirm() {
    HapticFeedback.mediumImpact();
    widget.onConfirm(_value);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final displayText = _typed.isEmpty
        ? 'No weight'
        : '${_typed.replaceAll(RegExp(r'\.0$'), '')} lbs';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).pop(),
        behavior: HitTestBehavior.opaque,
        child: Container(
          color: const Color(0xF2000000),
          child: SafeArea(
            child: GestureDetector(
              // Prevent dismissal when touching inner panel
              onTap: () {},
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
                    child: Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.09),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: const Icon(Icons.close_rounded,
                                size: 20, color: Colors.white54),
                          ),
                        ),
                        const Spacer(),
                        Text(
                          'WEIGHT',
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 3,
                            color: kLogPurple.withValues(alpha: 0.8),
                          ),
                        ),
                        const Spacer(),
                        const SizedBox(width: 36), // balance
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Big live display
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 140),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.12),
                          end: Offset.zero,
                        ).animate(anim),
                        child: child,
                      ),
                    ),
                    child: Text(
                      displayText,
                      key: ValueKey(displayText),
                      style: GoogleFonts.spaceMono(
                        fontSize: 52,
                        fontWeight: FontWeight.w700,
                        color: _typed.isEmpty
                            ? Colors.white.withValues(alpha: 0.2)
                            : kLogGold,
                        height: 1,
                      ),
                    ),
                  ),

                  const SizedBox(height: 28),

                  // Drum wheel
                  Expanded(
                    child: Stack(
                      children: [
                        // Wheel
                        ListWheelScrollView.useDelegate(
                          controller: _scroll,
                          itemExtent: _itemH,
                          perspective: 0.002,
                          diameterRatio: 2.8,
                          physics: const FixedExtentScrollPhysics(),
                          onSelectedItemChanged: _wheelChanged,
                          childDelegate: ListWheelChildBuilderDelegate(
                            childCount: _maxW.toInt() + 1,
                            builder: (_, i) {
                              final sel = i == _value.round() &&
                                  _typed.isNotEmpty &&
                                  !_typed.endsWith('.');
                              return Center(
                                child: Text(
                                  i == 0 ? '—' : '$i',
                                  style: GoogleFonts.spaceMono(
                                    fontSize: sel ? 42 : 28,
                                    fontWeight: FontWeight.w700,
                                    color: sel
                                        ? Colors.white
                                        : Colors.white
                                            .withValues(alpha: 0.18),
                                    height: 1,
                                  ),
                                ),
                              );
                            },
                          ),
                        ),

                        // Selection band
                        IgnorePointer(
                          child: Center(
                            child: Container(
                              height: _itemH,
                              decoration: BoxDecoration(
                                border: Border.symmetric(
                                  horizontal: BorderSide(
                                    color: kLogPurple.withValues(alpha: 0.4),
                                    width: 1.0,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Top fade
                        IgnorePointer(
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Container(
                              height: _itemH * ((_visibleItems - 1) / 2),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    const Color(0xF2000000),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        // Bottom fade
                        IgnorePointer(
                          child: Align(
                            alignment: Alignment.bottomCenter,
                            child: Container(
                              height: _itemH * ((_visibleItems - 1) / 2),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    const Color(0xF2000000),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Number pad
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
                    child: _NumPad(onKey: _numPad),
                  ),

                  const SizedBox(height: 16),

                  // Confirm button
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: GestureDetector(
                      onTap: _confirm,
                      child: Container(
                        height: 58,
                        decoration: BoxDecoration(
                          color: _typed.isEmpty ? kLogSurface : kLogPurple,
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: _typed.isNotEmpty
                              ? [
                                  BoxShadow(
                                    color: kLogPurple.withValues(alpha: 0.4),
                                    blurRadius: 20,
                                    spreadRadius: -4,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(
                            _typed.isEmpty
                                ? 'No weight'
                                : 'Set ${_value % 1 == 0 ? _value.toInt() : _value.toStringAsFixed(1)} lbs',
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: _typed.isEmpty
                                  ? Colors.white.withValues(alpha: 0.3)
                                  : Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Number pad
// ─────────────────────────────────────────────────────────────────────────────

class _NumPad extends StatelessWidget {
  final ValueChanged<String> onKey;
  const _NumPad({required this.onKey});

  static const _rows = [
    ['1', '2', '3'],
    ['4', '5', '6'],
    ['7', '8', '9'],
    ['.', '0', '⌫'],
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: _rows.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Row(
            children: row.map((k) {
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  child: _NumKey(label: k, onTap: () => onKey(k)),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }
}

class _NumKey extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _NumKey({required this.label, required this.onTap});

  @override
  State<_NumKey> createState() => _NumKeyState();
}

class _NumKeyState extends State<_NumKey> with SingleTickerProviderStateMixin {
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
      },
      onTapCancel: () => _press.reverse(),
      child: AnimatedBuilder(
        animation: _press,
        builder: (_, __) {
          final t = _press.value;
          return Transform.scale(
            scale: 1.0 - 0.06 * t,
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Color.lerp(
                  Colors.white.withValues(alpha: 0.08),
                  kLogPurple.withValues(alpha: 0.3),
                  t,
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: widget.label == '⌫'
                    ? Icon(Icons.backspace_outlined,
                        size: 20,
                        color: Colors.white.withValues(alpha: 0.65))
                    : Text(
                        widget.label,
                        style: GoogleFonts.spaceMono(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: 0.9),
                          height: 1,
                        ),
                      ),
              ),
            ),
          );
        },
      ),
    );
  }
}
