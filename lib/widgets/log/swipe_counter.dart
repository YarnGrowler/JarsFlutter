import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/theme.dart';

class SwipeCounter extends StatefulWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final int min;
  final int max;
  final String label;

  const SwipeCounter({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 999,
    this.label = 'reps',
  });

  @override
  State<SwipeCounter> createState() => _SwipeCounterState();
}

class _SwipeCounterState extends State<SwipeCounter> {
  double _dragAccumulator = 0;

  void _increment() {
    if (widget.value < widget.max) {
      HapticFeedback.selectionClick();
      widget.onChanged(widget.value + 1);
    }
  }

  void _decrement() {
    if (widget.value > widget.min) {
      HapticFeedback.selectionClick();
      widget.onChanged(widget.value - 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            GestureDetector(
              onTap: _decrement,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: JarsColors.surface,
                  border: Border.all(color: JarsColors.border),
                ),
                child: const Center(
                  child: Icon(Icons.remove, color: JarsColors.textSecondary),
                ),
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onHorizontalDragUpdate: (details) {
                _dragAccumulator += details.primaryDelta ?? 0;
                if (_dragAccumulator.abs() > 8) {
                  if (_dragAccumulator > 0) {
                    _increment();
                  } else {
                    _decrement();
                  }
                  _dragAccumulator = 0;
                }
              },
              child: Container(
                width: 100,
                height: 64,
                decoration: BoxDecoration(
                  color: JarsColors.surfaceRaised,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: JarsColors.primary, width: 2),
                ),
                child: Center(
                  child: Text(
                    '${widget.value}',
                    style: GoogleFonts.spaceMono(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: JarsColors.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 16),
            GestureDetector(
              onTap: _increment,
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: JarsColors.surface,
                  border: Border.all(color: JarsColors.border),
                ),
                child: const Center(
                  child: Icon(Icons.add, color: JarsColors.textSecondary),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          widget.label,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: JarsColors.textSecondary,
          ),
        ),
      ],
    );
  }
}
