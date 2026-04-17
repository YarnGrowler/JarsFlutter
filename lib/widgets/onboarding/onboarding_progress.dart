import 'package:flutter/material.dart';

import '../../core/theme.dart';

/// Pill-style step progress bar. Active step is a wider pill; previous steps
/// are fully filled; future steps are dim.
class OnboardingProgress extends StatelessWidget {
  const OnboardingProgress({
    super.key,
    required this.total,
    required this.current,
  });

  final int total;
  final int current;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(total, (i) {
        final isActive = i == current;
        final isDone = i < current;
        return Expanded(
          flex: isActive ? 2 : 1,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 340),
              curve: Curves.easeOutBack,
              height: 5,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(99),
                color: isDone || isActive
                    ? JarsColors.primary.withValues(
                        alpha: isActive ? 1.0 : 0.55,
                      )
                    : JarsColors.border,
              ),
            ),
          ),
        );
      }),
    );
  }
}
