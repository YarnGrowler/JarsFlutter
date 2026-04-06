import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/count_unit.dart';
import '../../../core/log_screen_style.dart';

/// Compact **rep / time wheel** for a bottom sheet: one clear column of numbers,
/// live updates via [onRepsChanged], no confirm button (parent dismisses the sheet).
class RadialRepPicker extends StatefulWidget {
  const RadialRepPicker({
    super.key,
    required this.initialValue,
    required this.onRepsChanged,
    this.countUnit = CountUnit.reps,
  });

  final int initialValue;
  final ValueChanged<int> onRepsChanged;
  final CountUnit countUnit;

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
              '${widget.countUnit.pickerHint} · swipe to change',
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

/// Two wheels — **minutes** (0–180) and **seconds** (0–59) — for plank / stopwatch UI.
/// [onTotalSecondsChanged] receives combined length in whole seconds (max ~3h).
class MinSecWheelPicker extends StatefulWidget {
  const MinSecWheelPicker({
    super.key,
    required this.initialTotalSeconds,
    required this.onTotalSecondsChanged,
  });

  final int initialTotalSeconds;
  final ValueChanged<int> onTotalSecondsChanged;

  static const maxMinutes = 180;
  static const maxTotalSeconds = maxMinutes * 60 + 59;

  @override
  State<MinSecWheelPicker> createState() => _MinSecWheelPickerState();
}

class _MinSecWheelPickerState extends State<MinSecWheelPicker> {
  static const _itemH = 56.0;
  static const _visibleItems = 5;

  late FixedExtentScrollController _minCtrl;
  late FixedExtentScrollController _secCtrl;
  late int _min;
  late int _sec;

  @override
  void initState() {
    super.initState();
    final t = widget.initialTotalSeconds.clamp(0, MinSecWheelPicker.maxTotalSeconds);
    _min = t ~/ 60;
    _sec = t % 60;
    _minCtrl = FixedExtentScrollController(initialItem: _min);
    _secCtrl = FixedExtentScrollController(initialItem: _sec);
  }

  @override
  void dispose() {
    _minCtrl.dispose();
    _secCtrl.dispose();
    super.dispose();
  }

  void _emit() {
    final total = (_min * 60 + _sec).clamp(0, MinSecWheelPicker.maxTotalSeconds);
    widget.onTotalSecondsChanged(total);
  }

  void _onMinChanged(int i) {
    final v = i.clamp(0, MinSecWheelPicker.maxMinutes);
    if (v == _min) return;
    HapticFeedback.selectionClick();
    setState(() => _min = v);
    _emit();
  }

  void _onSecChanged(int i) {
    final v = i.clamp(0, 59);
    if (v == _sec) return;
    HapticFeedback.selectionClick();
    setState(() => _sec = v);
    _emit();
  }

  Widget _wheel({
    required bool isMinute,
    required FixedExtentScrollController controller,
    required int itemCount,
    required ValueChanged<int> onChanged,
    required String label,
  }) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: kLogPurple.withValues(alpha: 0.75),
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: Stack(
              children: [
                ListWheelScrollView.useDelegate(
                  controller: controller,
                  itemExtent: _itemH,
                  perspective: 0.003,
                  diameterRatio: 2.2,
                  physics: const FixedExtentScrollPhysics(),
                  onSelectedItemChanged: onChanged,
                  childDelegate: ListWheelChildBuilderDelegate(
                    childCount: itemCount,
                    builder: (_, i) {
                      final sel = isMinute ? i == _min : i == _sec;
                      return Center(
                        child: Text(
                          '$i',
                          style: GoogleFonts.spaceMono(
                            fontSize: sel ? 34 : 20,
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
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: SizedBox(
        height: 260,
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
              'swipe to set duration',
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: kLogPurple.withValues(alpha: 0.85),
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _wheel(
                    isMinute: true,
                    controller: _minCtrl,
                    itemCount: MinSecWheelPicker.maxMinutes + 1,
                    onChanged: _onMinChanged,
                    label: 'min',
                  ),
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Text(
                      ':',
                      style: GoogleFonts.spaceMono(
                        fontSize: 28,
                        fontWeight: FontWeight.w300,
                        color: Colors.white.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  _wheel(
                    isMinute: false,
                    controller: _secCtrl,
                    itemCount: 60,
                    onChanged: _onSecChanged,
                    label: 'sec',
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
