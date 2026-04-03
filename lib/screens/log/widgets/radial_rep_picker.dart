import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/log_screen_style.dart';

/// Compact **rep wheel** for a bottom sheet: one clear column of numbers,
/// live updates via [onRepsChanged], no confirm button (parent dismisses the sheet).
class RadialRepPicker extends StatefulWidget {
  const RadialRepPicker({
    super.key,
    required this.initialValue,
    required this.onRepsChanged,
  });

  final int initialValue;
  final ValueChanged<int> onRepsChanged;

  @override
  State<RadialRepPicker> createState() => _RadialRepPickerState();
}

class _RadialRepPickerState extends State<RadialRepPicker> {
  static const _maxVal = 999;
  static const _itemH = 56.0;
  static const _visibleItems = 5;

  late FixedExtentScrollController _scroll;
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.initialValue.clamp(0, _maxVal);
    _scroll = FixedExtentScrollController(initialItem: _value);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _wheelChanged(int i) {
    final v = i.clamp(0, _maxVal);
    if (v == _value) return;
    HapticFeedback.selectionClick();
    setState(() => _value = v);
    widget.onRepsChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: SizedBox(
        height: 240,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'reps · swipe to change',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: kLogPurple.withValues(alpha: 0.85),
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Stack(
                children: [
                  ListWheelScrollView.useDelegate(
                    controller: _scroll,
                    itemExtent: _itemH,
                    perspective: 0.003,
                    diameterRatio: 2.4,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: _wheelChanged,
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: _maxVal + 1,
                      builder: (_, i) {
                        final sel = i == _value;
                        return Center(
                          child: Text(
                            '$i',
                            style: GoogleFonts.spaceMono(
                              fontSize: sel ? 36 : 22,
                              fontWeight: FontWeight.w700,
                              color: sel
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.14),
                              height: 1,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        height: _itemH,
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            horizontal: BorderSide(
                              color: kLogPurple.withValues(alpha: 0.45),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
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
                              const Color(0xFF111118),
                              const Color(0x00111118),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
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
                              const Color(0xFF111118),
                              const Color(0x00111118),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
