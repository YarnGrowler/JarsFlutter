import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/log_screen_style.dart';

/// Minimal full-height edge panel: dismiss by tapping outside (value commits automatically).
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
    transitionDuration: const Duration(milliseconds: 280),
    transitionBuilder: (ctx, anim, _, child) {
      final curve =
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      final h = MediaQuery.sizeOf(ctx).height;
      final panelW = (MediaQuery.sizeOf(ctx).width * 0.2).clamp(88.0, 118.0);
      return Stack(
        fit: StackFit.expand,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(ctx).pop(),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.5 * anim.value),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: SlideTransition(
              position:
                  Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
                      .animate(curve),
              child: SizedBox(
                height: h,
                width: panelW,
                child: child,
              ),
            ),
          ),
        ],
      );
    },
    pageBuilder: (ctx, anim, _) => _WeightPickerPage(
      initial: initial,
      onConfirm: onConfirm,
    ),
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

class _WeightPickerPage extends StatefulWidget {
  final double initial;
  final ValueChanged<double> onConfirm;

  const _WeightPickerPage({required this.initial, required this.onConfirm});

  @override
  State<_WeightPickerPage> createState() => _WeightPickerPageState();
}

class _WeightPickerPageState extends State<_WeightPickerPage> {
  static const _maxLbs = 999;
  static const _itemH = 40.0;

  late FixedExtentScrollController _scroll;
  late int _lbs;
  bool _committedOnClose = false;

  @override
  void initState() {
    super.initState();
    _lbs = widget.initial.round().clamp(0, _maxLbs);
    _scroll = FixedExtentScrollController(initialItem: _lbs);
  }

  @override
  void dispose() {
    if (!_committedOnClose) {
      _committedOnClose = true;
      widget.onConfirm(_lbs.toDouble());
    }
    _scroll.dispose();
    super.dispose();
  }

  void _wheelChanged(int i) {
    final v = i.clamp(0, _maxLbs);
    if (v == _lbs) return;
    HapticFeedback.selectionClick();
    setState(() => _lbs = v);
  }

  void _commitOnce() {
    if (_committedOnClose) return;
    _committedOnClose = true;
    widget.onConfirm(_lbs.toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.paddingOf(context).top;
    final bottomPad = MediaQuery.paddingOf(context).bottom;

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) _commitOnce();
      },
      child: Material(
        color: const Color(0xF0101014),
        child: Column(
          children: [
            SizedBox(height: topPad + 20),
            Text(
              'WEIGHT',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                letterSpacing: 3,
                color: Colors.white.withValues(alpha: 0.45),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'LB',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 34,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
                color: kLogPurple.withValues(alpha: 0.95),
                height: 1,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'pounds',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.32),
              ),
            ),
            SizedBox(height: 18),
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ListWheelScrollView.useDelegate(
                    controller: _scroll,
                    itemExtent: _itemH,
                    diameterRatio: 2.4,
                    perspective: 0.002,
                    offAxisFraction: 0,
                    physics: const FixedExtentScrollPhysics(),
                    onSelectedItemChanged: _wheelChanged,
                    childDelegate: ListWheelChildBuilderDelegate(
                      childCount: _maxLbs + 1,
                      builder: (_, i) {
                        final sel = i == _lbs;
                        return Center(
                          child: Text(
                            i == 0 ? '—' : '$i',
                            style: GoogleFonts.spaceMono(
                              fontSize: sel ? 26 : 17,
                              fontWeight: FontWeight.w600,
                              color: sel
                                  ? Colors.white.withValues(alpha: 0.92)
                                  : Colors.white.withValues(alpha: 0.14),
                              height: 1,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  IgnorePointer(
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: Container(
                        height: 120,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xF0101014),
                              Color(0x00101014),
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
                        height: 120,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [
                              Color(0xF0101014),
                              Color(0x00101014),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  IgnorePointer(
                    child: Center(
                      child: Container(
                        height: _itemH,
                        decoration: BoxDecoration(
                          border: Border.symmetric(
                            horizontal: BorderSide(
                              color: Colors.white.withValues(alpha: 0.08),
                              width: 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: bottomPad + 12),
          ],
        ),
      ),
    );
  }
}
